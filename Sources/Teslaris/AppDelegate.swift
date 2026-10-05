//
//  AppDelegate.swift
//  Teslaris
//

import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusController: StatusItemController!
    private var settingsController: SettingsWindowController?

    /// Demo mode swaps the whole backend for a scripted timeline:
    ///   defaults write com.weareheavy.teslaris debug_demo_mode -bool YES
    private lazy var source: VehicleDataSource =
        DemoVehicleSource.enabled ? DemoVehicleSource() : fleetAPI
    private let fleetAPI = TeslaFleetAPI()

    private let notifier = Notifier()
    private let updater = Updater()
    private var refreshTimer: Timer?
    private var latest: VehicleData?
    private var lastError: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()

        statusController = StatusItemController(
            onRefresh: { [weak self] in self?.refreshNow() },
            onSettings: { [weak self] in self?.showSettings() }
        )
        statusController.onSelectVehicle = { [weak self] vin in self?.switchVehicle(to: vin) }
        if updater.isAvailable {
            statusController.onCheckForUpdates = { [weak self] in self?.updater.checkForUpdates() }
        }
        // The render arrives after the first poll has already been
        // published, so the widget gets a second pass once it is there.
        statusController.onCarImageLoaded = { [weak self] in self?.publishToWidget() }
        statusController.render(data: nil, error: nil, authenticated: false)
        notifier.requestAuthorizationIfNeeded()

        if hasCredentials || DemoVehicleSource.enabled {
            startSession()
        } else {
            showSettings()
        }
    }

    /// teslaris://open — sent by a click on the desktop widget.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard urls.contains(where: { $0.scheme == "teslaris" }) else { return }
        statusController.popMenu()
    }

    /// Menu-bar-only apps have no visible main menu, but key equivalents
    /// (⌘C/⌘V/⌘X/⌘A/⌘Z) are routed through NSApp.mainMenu — without an
    /// Edit menu, paste doesn't work in our settings window.
    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Teslaris",
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }

    private var hasCredentials: Bool {
        guard !Preferences.clientId.isEmpty else { return false }
        return ((try? Keychain.readRefreshToken()) ?? nil)?.isEmpty == false
    }

    // MARK: - Session lifecycle

    func startSession() {
        statusController.showLoading()
        Task {
            do {
                try await source.restoreSession()
                let data = try await source.fetchVehicleData(vin: Preferences.vin)
                await MainActor.run { self.apply(data) }
            } catch TeslarisError.vehicleAsleep {
                await MainActor.run { self.applyAsleep() }
            } catch {
                await MainActor.run {
                    self.lastError = error.localizedDescription
                    self.statusController.render(data: self.latest, error: error.localizedDescription,
                                                 authenticated: false)
                    // A dead session is "not signed in", not a transient
                    // error: open Settings so the fix is in reach instead
                    // of only an error row in the menu.
                    if Self.isSignedOut(error) {
                        WidgetBridge.clear()
                        self.showSettings()
                    }
                }
            }
        }
    }

    /// True when the session is gone rather than the network being flaky —
    /// no stored credentials, or Tesla rejecting the refresh token.
    static func isSignedOut(_ error: Error) -> Bool {
        switch error {
        case TeslarisError.notConfigured, TeslarisError.authenticationFailed:
            return true
        default:
            return false
        }
    }

    /// Runs the interactive browser sign-in, then loads data. Called from
    /// the settings window.
    func signInAndStart() {
        statusController.showLoading()
        Task {
            do {
                try await fleetAPI.signIn()
                await MainActor.run { self.refreshNow() }
            } catch {
                await MainActor.run {
                    self.lastError = error.localizedDescription
                    self.statusController.render(data: self.latest, error: error.localizedDescription,
                                                 authenticated: false)
                }
            }
        }
    }

    func refreshNow() {
        guard source.isAuthenticated else { startSession(); return }
        Task {
            do {
                let data = try await source.fetchVehicleData(vin: Preferences.vin)
                await MainActor.run { self.apply(data) }
            } catch TeslarisError.vehicleAsleep {
                await MainActor.run { self.applyAsleep() }
            } catch {
                await MainActor.run {
                    self.lastError = error.localizedDescription
                    self.statusController.render(data: self.latest, error: error.localizedDescription,
                                                 authenticated: true)
                }
            }
        }
    }

    private func apply(_ data: VehicleData) {
        notifier.vehicleDataDidUpdate(old: latest, new: data)
        latest = data
        lastError = nil
        statusController.vehicles = source.vehicles
        statusController.activeVin = Preferences.vin.isEmpty
            ? source.vehicles.first?.vin : Preferences.vin
        statusController.render(data: data, error: nil, authenticated: true)
        publishToWidget()
        scheduleRefresh()
    }

    private func publishToWidget() {
        guard let latest else { return }
        WidgetBridge.publish(latest, image: statusController.widgetImage(for: latest))
    }

    /// A sleeping car is not an error: keep showing the last known data,
    /// flagged as such. Never wake it — wakes cost money and battery.
    private func applyAsleep() {
        if let latest {
            self.latest = latest.asAsleep()
            notifier.vehicleIsAsleep(cached: latest)
        }
        lastError = nil
        statusController.render(data: latest, error: nil, authenticated: true)
        publishToWidget()
        scheduleRefresh()
    }

    private func switchVehicle(to vin: String) {
        Preferences.vin = vin
        latest = nil   // old car's data must not seed notifications
        statusController.showLoading()
        refreshNow()
    }

    private func scheduleRefresh() {
        let interval = Self.refreshInterval(for: latest,
                                            monthlyRequests: UsageMeter.monthlyCount)
        if let timer = refreshTimer, timer.isValid, timer.timeInterval == interval { return }
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.refreshNow()
        }
    }

    /// Poll cadence by state, tuned for Fleet API billing (~$0.002 per
    /// request). Parked: the pace chosen in Settings, 15 min by default —
    /// the numbers barely move, and every awake check is a billed request
    /// that also postpones the car falling asleep. Charging scales with
    /// time-to-full, so an overnight charge doesn't burn a request a minute
    /// for eight hours; the 1-minute cadence is saved for the last stretch,
    /// when the numbers actually matter. A charge is never polled more
    /// slowly than a parked car, or choosing a fast pace would make the
    /// menu go quieter the moment the cable goes in. Asleep is checked
    /// first and ignores the setting: a stale "Charging" state or an eager
    /// choice must never keep a sleeping car on a fast poll. Near the $10
    /// free credit the brake takes over: at least 30 minutes, and never
    /// faster than the credits that are left can sustain until they reset —
    /// a fixed 30 minutes alone would still run past the allowance if the
    /// brake engaged early in the month. With nothing left, polling waits
    /// for the reset.
    static func refreshInterval(for data: VehicleData?,
                                monthlyRequests: Int,
                                parked: RefreshInterval = Preferences.refreshInterval,
                                now: Date = Date()) -> TimeInterval {
        let parkedInterval = TimeInterval(parked.rawValue)
        var interval = parkedInterval
        if let data {
            if data.isAsleep {
                interval = 1800
            } else if data.isCharging {
                let minutes = data.minutesToFull ?? 0
                let charging: TimeInterval = minutes > 60 ? 300 : (minutes > 15 ? 120 : 60)
                interval = min(charging, parkedInterval)
            }
        }
        if monthlyRequests >= UsageMeter.brakeThreshold {
            let untilReset = UsageMeter.secondsLeftInMonth(from: now)
            let remaining = UsageMeter.monthlyAllowance - monthlyRequests
            guard remaining > 0 else { return max(untilReset, 60) }
            interval = max(interval * 2, 1800, untilReset / Double(remaining))
        }
        return interval
    }

    // MARK: - Settings

    func showSettings() {
        if settingsController == nil {
            settingsController = SettingsWindowController(
                onSave: { [weak self] in
                    self?.applyLaunchAtLogin()
                    // A new parked pace takes effect now, not after the old
                    // timer has run its full course — and still holds if the
                    // fetch below fails and never reaches apply(). Only an
                    // existing timer is replaced: starting one before any
                    // session exists would retry a missing sign-in, and
                    // reopen Settings, every few minutes.
                    if self?.refreshTimer != nil { self?.scheduleRefresh() }
                    self?.startSession()
                },
                onSignIn: { [weak self] in
                    self?.applyLaunchAtLogin()
                    self?.signInAndStart()
                },
                onRegister: { [weak self] domain in
                    self?.registerPartnerAccount(domain: domain)
                },
                updater: updater
            )
        }
        settingsController?.show()
    }

    /// One-time partner registration against Tesla, reporting the outcome
    /// in an alert. Failure here is common (key not yet reachable), so the
    /// error text carries the URL Tesla checks.
    private func registerPartnerAccount(domain: String) {
        Task {
            do {
                let summary = try await fleetAPI.registerPartnerAccount(domain: domain)
                await MainActor.run {
                    self.showAlert(title: "Registered with Tesla",
                                   text: "Registered \(domain) in every region:\n\n\(summary)"
                                       + "\n\nYou can sign in now.")
                }
            } catch {
                await MainActor.run {
                    self.showAlert(title: "Registration failed",
                                   text: "One or more regions failed. You sign in against "
                                       + "your account's own region, so that one must "
                                       + "succeed:\n\n\(error.localizedDescription)")
                }
            }
        }
    }

    private func showAlert(title: String, text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.runModal()
    }

    private func applyLaunchAtLogin() {
        // SMAppService only works from a real .app bundle (make app),
        // not when running the bare binary via `swift run`.
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        do {
            if Preferences.launchAtLogin {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            NSLog("Launch-at-login change failed: \(error.localizedDescription)")
        }
    }
}
