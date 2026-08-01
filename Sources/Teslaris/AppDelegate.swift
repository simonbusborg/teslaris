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
                }
            }
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

    /// Poll every minute while charging (the numbers actually move).
    /// Idle polling is 15 minutes — every request costs Fleet API credit,
    /// and a parked car's numbers barely change.
    private func scheduleRefresh() {
        let interval: TimeInterval = (latest?.isCharging == true) ? 60 : 900
        if let timer = refreshTimer, timer.isValid, timer.timeInterval == interval { return }
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.refreshNow()
        }
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
                try await fleetAPI.registerPartnerAccount(domain: domain)
                await MainActor.run {
                    self.showAlert(title: "Registered with Tesla",
                                   text: "Your app is registered for \(domain). "
                                       + "You can sign in now.")
                }
            } catch {
                await MainActor.run {
                    self.showAlert(title: "Registration failed",
                                   text: error.localizedDescription)
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
