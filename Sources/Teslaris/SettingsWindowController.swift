//
//  SettingsWindowController.swift
//  Teslaris
//
//  A small programmatic settings window. Unlike Polaris there is no
//  password field: the user pastes the credentials of their own Tesla
//  developer application (see the setup guide in the README), then signs
//  in via the browser.
//

import AppKit

final class SettingsWindowController: NSWindowController, NSWindowDelegate, NSTextFieldDelegate, NSTextViewDelegate {

    private let methodPopup = NSPopUpButton()
    /// A Tesla refresh token is an ~800-character JWT — a single-line
    /// field shows a useless sliver of it, so this is a small scrolling
    /// text view instead.
    private let ownerTokenView = NSTextView()
    private let ownerTokenScroll = NSScrollView()
    private let ownerHelp = NSTextField(labelWithString: "")
    private let ownerStatus = NSTextField(labelWithString: "")
    /// Rows belonging to each method, hidden when the other is chosen.
    private var ownerRowRange: [NSGridRow] = []
    private var fleetRowRange: [NSGridRow] = []

    private let clientIdField = NSTextField()
    private let clientSecretField = NSSecureTextField()
    private let domainField = NSTextField()
    private let regionPopup = NSPopUpButton()
    private let displayPopup = NSPopUpButton()
    private let unitPopup = NSPopUpButton()
    private let launchCheckbox = NSButton(checkboxWithTitle: "Launch at login", target: nil, action: nil)
    private let notifyStartCheckbox = NSButton(checkboxWithTitle: "Charging started", target: nil, action: nil)
    private let notifyDoneCheckbox = NSButton(checkboxWithTitle: "Charging complete", target: nil, action: nil)
    private let notifyProblemCheckbox = NSButton(checkboxWithTitle: "Charging problems", target: nil, action: nil)

    /// Held so the key-hosting action can show progress on it.
    private weak var keyHostingButton: NSButton?

    /// Inline verdicts, so a wrong value is caught where it is typed
    /// rather than several steps later.
    private let domainStatus = NSTextField(labelWithString: "")
    private let credentialStatus = NSTextField(labelWithString: "")
    /// What we last checked, so leaving a field untouched doesn't
    /// re-hit Tesla on every focus change.
    private var checkedCredentials: String?
    private var checkedDomain: String?
    private var checkedOwnerToken: String?

    private let onSave: () -> Void
    private let onSignIn: () -> Void
    private let onRegister: (String) -> Void

    init(onSave: @escaping () -> Void, onSignIn: @escaping () -> Void,
         onRegister: @escaping (String) -> Void) {
        self.onSave = onSave
        self.onSignIn = onSignIn
        self.onRegister = onRegister

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Teslaris Settings"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func show() {
        loadValues()
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - UI

    private func buildUI() {
        guard let content = window?.contentView else { return }

        clientIdField.placeholderString = "Tesla developer app Client ID"
        clientSecretField.placeholderString = "Client Secret"
        domainField.placeholderString = "Click Set Up Key Hosting →"
        // Editable text fields have no useful intrinsic width; without one,
        // the grid hands the window's spare width to the label column and
        // the whole form ends up shoved against the right edge.
        // Wide enough for a full 36-character Tesla client ID in the
        // monospaced face below — at 270pt a pasted UUID scrolled out of
        // sight and looked truncated. Monospaced also makes these
        // opaque strings checkable character by character.
        for field in [clientIdField, clientSecretField, domainField] {
            field.translatesAutoresizingMaskIntoConstraints = false
            field.widthAnchor.constraint(equalToConstant: 340).isActive = true
            field.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        }

        regionPopup.removeAllItems()
        for region in Region.allCases { regionPopup.addItem(withTitle: region.rawValue) }
        displayPopup.removeAllItems()
        for option in DisplayOption.allCases { displayPopup.addItem(withTitle: option.rawValue) }
        unitPopup.removeAllItems()
        for unit in DistanceUnit.allCases { unitPopup.addItem(withTitle: unit.rawValue) }

        let guideLink = NSTextField(labelWithString: "Use the key domain as the Allowed Origin when you create your (free) Tesla developer app — see the setup guide.")
        guideLink.font = .systemFont(ofSize: 11)
        guideLink.textColor = .secondaryLabelColor
        guideLink.lineBreakMode = .byWordWrapping
        guideLink.preferredMaxLayoutWidth = 340

        let generateKeysButton = NSButton(title: "Set Up Key Hosting",
                                         target: self, action: #selector(generateKeysAction))
        keyHostingButton = generateKeysButton
        let registerButton = NSButton(title: "Register App with Tesla",
                                      target: self, action: #selector(registerAction))

        methodPopup.removeAllItems()
        for method in AuthMethod.allCases { methodPopup.addItem(withTitle: method.rawValue) }
        methodPopup.target = self
        methodPopup.action = #selector(methodChanged)

        // A refresh token is an ~800-character JWT, so it gets a small
        // scrolling text view rather than a one-line field.
        ownerTokenView.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        ownerTokenView.isRichText = false
        ownerTokenView.isAutomaticQuoteSubstitutionEnabled = false
        ownerTokenView.isAutomaticDashSubstitutionEnabled = false
        ownerTokenView.delegate = self
        ownerTokenScroll.documentView = ownerTokenView
        ownerTokenScroll.hasVerticalScroller = true
        ownerTokenScroll.borderType = .bezelBorder
        ownerTokenScroll.translatesAutoresizingMaskIntoConstraints = false
        ownerTokenScroll.widthAnchor.constraint(equalToConstant: 340).isActive = true
        ownerTokenScroll.heightAnchor.constraint(equalToConstant: 64).isActive = true

        ownerHelp.stringValue = "No developer account needed. Generate a token with "
            + "\"Auth App for Tesla\" (iOS) or \"Tesla Tokens\" (Android), then paste it here."
        for hint in [ownerHelp, ownerStatus] {
            hint.font = .systemFont(ofSize: 11)
            hint.textColor = .secondaryLabelColor
            hint.lineBreakMode = .byWordWrapping
            hint.preferredMaxLayoutWidth = 340
        }

        // Ordered as the setup guide runs: get a key domain, take it to
        // Tesla, come back with the credentials it gives you.
        for status in [domainStatus, credentialStatus] {
            status.font = .systemFont(ofSize: 11)
            status.textColor = .secondaryLabelColor
            status.lineBreakMode = .byWordWrapping
            status.preferredMaxLayoutWidth = 340
        }
        clientIdField.delegate = self
        clientSecretField.delegate = self
        domainField.delegate = self

        let grid = NSGridView(views: [
            [label("Sign in with:"), methodPopup],
            [label("Refresh token:"), ownerTokenScroll],
            [NSGridCell.emptyContentView, ownerStatus],
            [NSGridCell.emptyContentView, ownerHelp],
            [label("Key domain:"), domainField],
            [NSGridCell.emptyContentView, domainStatus],
            [NSGridCell.emptyContentView, generateKeysButton],
            [NSGridCell.emptyContentView, guideLink],
            [label("Client ID:"), clientIdField],
            [label("Client Secret:"), clientSecretField],
            [NSGridCell.emptyContentView, credentialStatus],
            [label("Region:"), regionPopup],
            [NSGridCell.emptyContentView, registerButton],
            [label("Show in bar:"), displayPopup],
            [label("Distances:"), unitPopup],
            [NSGridCell.emptyContentView, launchCheckbox],
            [label("Notify about:"), notifyStartCheckbox],
            [NSGridCell.emptyContentView, notifyDoneCheckbox],
            [NSGridCell.emptyContentView, notifyProblemCheckbox]
        ])
        grid.rowSpacing = 12
        grid.columnSpacing = 10
        grid.rowAlignment = .firstBaseline
        grid.column(at: 0).xPlacement = .trailing
        for control in [regionPopup, displayPopup, unitPopup, launchCheckbox,
                        generateKeysButton, registerButton, domainStatus, credentialStatus,
                        notifyStartCheckbox, notifyDoneCheckbox, notifyProblemCheckbox] as [NSView] {
            grid.cell(for: control)?.xPlacement = .leading
        }
        grid.row(at: 1).topPadding = 12    // credentials group
        grid.row(at: 2).topPadding = -6    // verdict hugs the token field
        grid.row(at: 3).topPadding = -4    // help hugs the verdict
        grid.row(at: 5).topPadding = -6    // verdict hugs the domain field
        grid.row(at: 6).topPadding = -2    // button under it
        grid.row(at: 7).topPadding = -4    // hint hugs the button
        grid.row(at: 8).topPadding = 12    // Fleet credentials group
        grid.row(at: 10).topPadding = -6   // verdict hugs the secret field
        grid.row(at: 12).topPadding = -2   // Register hugs its inputs
        grid.row(at: 13).topPadding = 14   // display preferences
        grid.row(at: 16).topPadding = 10   // notifications
        grid.row(at: 17).topPadding = -6
        grid.row(at: 18).topPadding = -6

        // Only one method's fields are relevant at a time.
        ownerRowRange = (1...3).map { grid.row(at: $0) }
        fleetRowRange = (4...12).map { grid.row(at: $0) }
        applyMethodVisibility()
        grid.translatesAutoresizingMaskIntoConstraints = false

        let signInButton = NSButton(title: "Save & Sign in with Tesla…",
                                    target: self, action: #selector(signInAction))
        signInButton.keyEquivalent = "\r"
        let saveButton = NSButton(title: "Save", target: self, action: #selector(saveAction))
        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancelAction))
        cancelButton.keyEquivalent = "\u{1b}"

        let buttons = NSStackView(views: [cancelButton, saveButton, signInButton])
        buttons.orientation = .horizontal
        buttons.spacing = 12
        buttons.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(grid)
        content.addSubview(buttons)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            grid.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            grid.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -20),
            buttons.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 20),
            buttons.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            buttons.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20)
        ])

        window?.setContentSize(NSSize(width: 520, height: content.fittingSize.height))
    }

    private func label(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.alignment = .right
        return l
    }

    private func loadValues() {
        methodPopup.selectItem(withTitle: Preferences.authMethod.rawValue)
        ownerTokenView.string = ((try? Keychain.readOwnerRefreshToken()) ?? nil) ?? ""
        applyMethodVisibility()
        clientIdField.stringValue = Preferences.clientId
        clientSecretField.stringValue = ((try? Keychain.readClientSecret()) ?? nil) ?? ""
        domainField.stringValue = Preferences.domain
        regionPopup.selectItem(withTitle: Preferences.region.rawValue)
        displayPopup.selectItem(withTitle: Preferences.displayOption.rawValue)
        unitPopup.selectItem(withTitle: Preferences.distanceUnit.rawValue)
        launchCheckbox.state = Preferences.launchAtLogin ? .on : .off
        notifyStartCheckbox.state = Preferences.notifyChargingStarted ? .on : .off
        notifyDoneCheckbox.state = Preferences.notifyChargingComplete ? .on : .off
        notifyProblemCheckbox.state = Preferences.notifyChargingProblem ? .on : .off
    }

    // MARK: - Sign-in method

    @objc private func methodChanged() {
        if let title = methodPopup.titleOfSelectedItem,
           let method = AuthMethod(rawValue: title) {
            Preferences.authMethod = method
        }
        applyMethodVisibility()
        window?.setContentSize(NSSize(width: 520,
                                      height: window?.contentView?.fittingSize.height ?? 300))
    }

    private func applyMethodVisibility() {
        let owner = Preferences.authMethod == .ownerAPI
        for row in ownerRowRange { row.isHidden = !owner }
        for row in fleetRowRange { row.isHidden = owner }
    }

    /// Proves a pasted refresh token works before it is relied on, so a
    /// bad paste is rejected here rather than as a menu-bar error later.
    func textDidEndEditing(_ notification: Notification) {
        guard (notification.object as? NSTextView) === ownerTokenView else { return }
        checkOwnerToken()
    }

    private func checkOwnerToken() {
        let token = ownerTokenView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { ownerStatus.stringValue = ""; return }
        guard token != checkedOwnerToken else { return }
        checkedOwnerToken = token

        setStatus(ownerStatus, "Checking with Tesla…", .secondaryLabelColor)
        Task {
            do {
                let api = TeslaOwnerAPI()
                try await api.signIn(refreshToken: token)
                _ = try? await api.fetchVehicleData(vin: "")
                let names = api.vehicles.map(\.title).joined(separator: ", ")
                await MainActor.run {
                    self.setStatus(self.ownerStatus,
                                   names.isEmpty ? "✓ Signed in"
                                                 : "✓ Signed in — \(names)",
                                   .systemGreen)
                }
            } catch {
                await MainActor.run {
                    self.checkedOwnerToken = nil
                    self.setStatus(self.ownerStatus, "✗ \(error.localizedDescription)",
                                   .systemOrange)
                }
            }
        }
    }

    // MARK: - Live validation

    /// Checks whatever the user just finished typing, so a wrong value
    /// is caught here instead of surfacing as an opaque Tesla error
    /// several steps later. Each check runs only when the value has
    /// actually changed.
    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        if field === domainField {
            checkDomain()
        } else if field === clientIdField || field === clientSecretField {
            checkCredentials()
        }
    }

    private func checkDomain() {
        let domain = domainField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !domain.isEmpty else { domainStatus.stringValue = ""; return }
        guard domain != checkedDomain else { return }
        checkedDomain = domain

        setStatus(domainStatus, "Checking the key is reachable…", .secondaryLabelColor)
        Task {
            let url = "https://\(domain)/\(KeyPair.wellKnownPath)"
            var request = URLRequest(url: URL(string: url) ?? URL(string: "https://invalid")!)
            request.timeoutInterval = 20
            let ok: Bool
            if let (data, response) = try? await URLSession.shared.data(for: request) {
                ok = (response as? HTTPURLResponse)?.statusCode == 200
                    && String(data: data, encoding: .utf8)?.contains("BEGIN PUBLIC KEY") == true
            } else {
                ok = false
            }
            await MainActor.run {
                if ok {
                    self.setStatus(self.domainStatus, "✓ Tesla can fetch your key here",
                                   .systemGreen)
                } else {
                    self.checkedDomain = nil   // let a retry re-check
                    self.setStatus(self.domainStatus,
                                   "✗ No public key served at this domain yet",
                                   .systemOrange)
                }
            }
        }
    }

    private func checkCredentials() {
        let id = clientIdField.stringValue.trimmingCharacters(in: .whitespaces)
        let secret = clientSecretField.stringValue
        guard !id.isEmpty, !secret.isEmpty else { credentialStatus.stringValue = ""; return }

        // A Tesla client ID is a UUID; say so before spending a request.
        guard id.count == 36, id.filter({ $0 == "-" }).count == 4 else {
            setStatus(credentialStatus,
                      "✗ A Client ID is 36 characters (8-4-4-4-12) — this one is \(id.count)",
                      .systemOrange)
            return
        }

        let fingerprint = "\(id)\u{1}\(secret)"
        guard fingerprint != checkedCredentials else { return }
        checkedCredentials = fingerprint

        setStatus(credentialStatus, "Checking with Tesla…", .secondaryLabelColor)
        Task {
            do {
                try await TeslaFleetAPI().validateCredentials(clientId: id, secret: secret)
                await MainActor.run {
                    self.regionPopup.selectItem(withTitle: Preferences.region.rawValue)
                    self.setStatus(self.credentialStatus,
                                   "✓ Tesla accepts these — region: \(Preferences.region.rawValue)",
                                   .systemGreen)
                }
            } catch {
                await MainActor.run {
                    self.checkedCredentials = nil
                    self.setStatus(self.credentialStatus, "✗ \(error.localizedDescription)",
                                   .systemOrange)
                }
            }
        }
    }

    private func setStatus(_ field: NSTextField, _ text: String, _ color: NSColor) {
        field.stringValue = text
        field.textColor = color
    }

    // MARK: - Actions

    /// Persists all fields. Returns false when the Keychain write failed.
    @discardableResult
    private func persist() -> Bool {
        if let title = methodPopup.titleOfSelectedItem,
           let method = AuthMethod(rawValue: title) {
            Preferences.authMethod = method
        }
        let ownerToken = ownerTokenView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        if ownerToken.isEmpty {
            Keychain.deleteOwnerRefreshToken()
        } else {
            try? Keychain.saveOwnerRefreshToken(ownerToken)
        }
        Preferences.clientId = clientIdField.stringValue.trimmingCharacters(in: .whitespaces)
        Preferences.domain = domainField.stringValue.trimmingCharacters(in: .whitespaces)
        if let title = regionPopup.titleOfSelectedItem, let region = Region(rawValue: title) {
            Preferences.region = region
        }
        if let title = displayPopup.titleOfSelectedItem,
           let option = DisplayOption(rawValue: title) {
            Preferences.displayOption = option
        }
        if let title = unitPopup.titleOfSelectedItem,
           let unit = DistanceUnit(rawValue: title) {
            Preferences.distanceUnit = unit
        }
        Preferences.launchAtLogin = (launchCheckbox.state == .on)
        Preferences.notifyChargingStarted = (notifyStartCheckbox.state == .on)
        Preferences.notifyChargingComplete = (notifyDoneCheckbox.state == .on)
        Preferences.notifyChargingProblem = (notifyProblemCheckbox.state == .on)

        let secret = clientSecretField.stringValue
        if secret.isEmpty {
            Keychain.deleteClientSecret()
        } else {
            do {
                try Keychain.saveClientSecret(secret)
            } catch {
                let alert = NSAlert()
                alert.messageText = "Couldn't save the client secret to Keychain"
                alert.informativeText = error.localizedDescription
                alert.runModal()
                return false
            }
        }
        return true
    }

    @objc private func saveAction() {
        guard persist() else { return }
        window?.orderOut(nil)
        onSave()
    }

    /// The whole key step in one button: generate the pair on this Mac,
    /// upload only the public half, and fill in the domain now serving
    /// it. No Terminal, no openssl, no hosting to arrange.
    @objc private func generateKeysAction() {
        let button = keyHostingButton
        button?.isEnabled = false
        button?.title = "Setting Up…"

        Task {
            let keys = KeyPair.generate()
            do {
                let domain = try await KeyHosting.host(publicPEM: keys.publicPEM)
                let reachable = await KeyHosting.verify(domain: domain,
                                                        expecting: keys.publicPEM)
                // Keep the private key: Teslaris never needs it, but the
                // user would if they ever move to Tesla's command API.
                var savedTo: URL?
                if let url = try? KeyHosting.privateKeyURL() {
                    try? keys.privatePEM.write(to: url, atomically: true, encoding: .utf8)
                    try? FileManager.default.setAttributes([.posixPermissions: 0o600],
                                                           ofItemAtPath: url.path)
                    savedTo = url
                }

                await MainActor.run {
                    self.domainField.stringValue = domain
                    self.setStatus(self.domainStatus,
                                   reachable ? "✓ Tesla can fetch your key here"
                                             : "Key uploaded — going live…",
                                   reachable ? .systemGreen : .secondaryLabelColor)
                    self.checkedDomain = reachable ? domain : nil
                    Preferences.domain = domain
                    button?.isEnabled = true
                    button?.title = "Set Up Key Hosting"

                    let alert = NSAlert()
                    alert.messageText = reachable ? "Key hosting is ready"
                                                  : "Key uploaded — still going live"
                    var text = """
                        Your public key is served at

                        \(domain)

                        That domain is filled in above. Use it as the \
                        Allowed Origin when you create your Tesla developer \
                        app, then click Register App with Tesla.
                        """
                    if !reachable {
                        text += "\n\nIt isn't answering yet — this usually "
                            + "takes a moment. Try Register in a minute."
                    }
                    if let savedTo {
                        text += "\n\nYour private key (which Teslaris never "
                            + "uses) is saved at \(savedTo.path)."
                    }
                    alert.informativeText = text
                    alert.addButton(withTitle: "OK")
                    alert.addButton(withTitle: "Open Tesla Developer Portal")
                    if alert.runModal() == .alertSecondButtonReturn,
                       let url = URL(string: "https://developer.tesla.com") {
                        NSWorkspace.shared.open(url)
                    }
                }
            } catch {
                await MainActor.run {
                    button?.isEnabled = true
                    button?.title = "Set Up Key Hosting"
                    let alert = NSAlert()
                    alert.messageText = "Couldn't set up key hosting"
                    alert.informativeText = error.localizedDescription
                        + "\n\nYou can also host the key yourself — see the "
                        + "setup guide — and type that domain above."
                    alert.addButton(withTitle: "OK")
                    alert.addButton(withTitle: "Open Setup Guide")
                    if alert.runModal() == .alertSecondButtonReturn,
                       let url = URL(string: "https://simonbusborg.github.io/teslaris/#setup") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
    }

    /// One-time partner registration, run by the app instead of the old
    /// curl incantation. Keeps the window open so Sign in follows.
    @objc private func registerAction() {
        guard persist() else { return }
        let domain = Preferences.domain
        guard !domain.isEmpty else {
            let alert = NSAlert()
            alert.messageText = "Key domain needed"
            alert.informativeText = "Enter the domain that hosts your public key "
                + "(e.g. username.github.io) so Tesla can verify it."
            alert.runModal()
            return
        }
        onRegister(domain)
    }

    @objc private func signInAction() {
        guard persist() else { return }
        // The simple route has no browser step — the pasted token *is*
        // the session, so just start using it.
        if Preferences.authMethod == .ownerAPI {
            window?.orderOut(nil)
            onSave()
            return
        }
        // New credentials invalidate the old Fleet session.
        Keychain.deleteRefreshToken()
        window?.orderOut(nil)
        onSignIn()
    }

    @objc private func cancelAction() {
        window?.orderOut(nil)
    }
}
