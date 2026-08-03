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
    private var source: VehicleDataSource {
        if DemoVehicleSource.enabled { return demoSource }
        return Preferences.authMethod == .ownerAPI ? ownerAPI : fleetAPI
    }
    private let demoSource = DemoVehicleSource()
    private let fleetAPI = TeslaFleetAPI()
    private let ownerAPI = TeslaOwnerAPI()

    private let notifier = Notifier()
    private let updateChecker = UpdateChecker()
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
        statusController.render(data: nil, error: nil, authenticated: false)
        notifier.requestAuthorizationIfNeeded()
        updateChecker.checkIfDue { [weak self] version in
            guard let self else { return }
            self.statusController.updateVersion = version
            self.statusController.render(data: self.latest, error: self.lastError,
                                         authenticated: self.source.isAuthenticated)
        }

        if hasCredentials || DemoVehicleSource.enabled {
            startSession()
        } else {
            showSettings()
        }
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
        switch Preferences.authMethod {
        case .ownerAPI:
            return ((try? Keychain.readOwnerRefreshToken()) ?? nil)?.isEmpty == false
        case .fleetAPI:
            guard !Preferences.clientId.isEmpty else { return false }
            return ((try? Keychain.readRefreshToken()) ?? nil)?.isEmpty == false
        }
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
                    if Self.isSignedOut(error) { self.showSettings() }
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
        scheduleRefresh()
    }

    /// A sleeping car is not an error: keep showing the last known data,
    /// flagged as such. Never wake it — wakes cost money and battery.
    private func applyAsleep() {
        if let latest {
            self.latest = latest.asAsleep()
        }
        lastError = nil
        statusController.render(data: latest, error: nil, authenticated: true)
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
    /// request). Parked: 15 min — the numbers barely move. Charging
    /// scales with time-to-full, so an overnight charge doesn't burn a
    /// request a minute for eight hours; the 1-minute cadence is saved
    /// for the last stretch, when the numbers actually matter. Asleep is
    /// checked first: a stale "Charging" state must never keep a
    /// sleeping car on a fast poll. Near the $10 free credit, the brake
    /// stretches everything to 30 minutes.
    static func refreshInterval(for data: VehicleData?,
                                monthlyRequests: Int) -> TimeInterval {
        var interval: TimeInterval = 900
        if let data {
            if data.isAsleep {
                interval = 1800
            } else if data.isCharging {
                let minutes = data.minutesToFull ?? 0
                interval = minutes > 60 ? 300 : (minutes > 15 ? 120 : 60)
            }
        }
        if monthlyRequests >= UsageMeter.brakeThreshold {
            interval = max(interval * 2, 1800)
        }
        return interval
    }

    // MARK: - Settings

    func showSettings() {
        if settingsController == nil {
            settingsController = SettingsWindowController(
                onSave: { [weak self] in
                    self?.applyLaunchAtLogin()
                    self?.startSession()
                },
                onSignIn: { [weak self] in
                    self?.applyLaunchAtLogin()
                    self?.signInAndStart()
                },
                onRegister: { [weak self] domain in
                    self?.registerPartnerAccount(domain: domain)
                }
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
