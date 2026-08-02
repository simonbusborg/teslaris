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

final class SettingsWindowController: NSWindowController, NSWindowDelegate {

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

    private let onSave: () -> Void
    private let onSignIn: () -> Void
    private let onRegister: (String) -> Void

    init(onSave: @escaping () -> Void, onSignIn: @escaping () -> Void,
         onRegister: @escaping (String) -> Void) {
        self.onSave = onSave
        self.onSignIn = onSignIn
        self.onRegister = onRegister

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 300),
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
        domainField.placeholderString = "username.github.io (hosts your public key)"
        // Editable text fields have no useful intrinsic width; without one,
        // the grid hands the window's spare width to the label column and
        // the whole form ends up shoved against the right edge.
        for field in [clientIdField, clientSecretField, domainField] {
            field.translatesAutoresizingMaskIntoConstraints = false
            field.widthAnchor.constraint(equalToConstant: 270).isActive = true
        }

        regionPopup.removeAllItems()
        for region in Region.allCases { regionPopup.addItem(withTitle: region.rawValue) }
        displayPopup.removeAllItems()
        for option in DisplayOption.allCases { displayPopup.addItem(withTitle: option.rawValue) }
        unitPopup.removeAllItems()
        for unit in DistanceUnit.allCases { unitPopup.addItem(withTitle: unit.rawValue) }

        let guideLink = NSTextField(labelWithString: "Requires your own (free) Tesla developer app — see the setup guide.")
        guideLink.font = .systemFont(ofSize: 11)
        guideLink.textColor = .secondaryLabelColor
        guideLink.lineBreakMode = .byWordWrapping
        guideLink.preferredMaxLayoutWidth = 270

        let generateKeysButton = NSButton(title: "Generate Key Pair…",
                                         target: self, action: #selector(generateKeysAction))
        let registerButton = NSButton(title: "Register App with Tesla",
                                      target: self, action: #selector(registerAction))
        let keyRow = NSStackView(views: [generateKeysButton, registerButton])
        keyRow.orientation = .horizontal
        keyRow.spacing = 8

        let grid = NSGridView(views: [
            [label("Client ID:"), clientIdField],
            [label("Client Secret:"), clientSecretField],
            [label("Key domain:"), domainField],
            [label("Region:"), regionPopup],
            [NSGridCell.emptyContentView, guideLink],
            [NSGridCell.emptyContentView, keyRow],
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
        for control in [regionPopup, displayPopup, unitPopup, launchCheckbox, keyRow,
                        notifyStartCheckbox, notifyDoneCheckbox, notifyProblemCheckbox] as [NSView] {
            grid.cell(for: control)?.xPlacement = .leading
        }
        grid.row(at: 4).topPadding = -6
        grid.row(at: 5).topPadding = -4
        grid.row(at: 6).topPadding = 10
        grid.row(at: 9).topPadding = 10
        grid.row(at: 10).topPadding = -6
        grid.row(at: 11).topPadding = -6
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

        window?.setContentSize(NSSize(width: 440, height: content.fittingSize.height))
    }

    private func label(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.alignment = .right
        return l
    }

    private func loadValues() {
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

    // MARK: - Actions

    /// Persists all fields. Returns false when the Keychain write failed.
    @discardableResult
    private func persist() -> Bool {
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

    /// Generates the Tesla key pair on this Mac — no Terminal, no
    /// openssl. Writes both PEMs to a folder the user picks and reveals
    /// the public one, which is the file that has to be hosted.
    @objc private func generateKeysAction() {
        let panel = NSOpenPanel()
        panel.message = "Choose where to save your Tesla key pair"
        panel.prompt = "Save Here"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory,
                                                      in: .userDomainMask).first
        guard panel.runModal() == .OK, let directory = panel.url else { return }

        do {
            let keys = KeyPair.generate()
            let publicURL = try KeyPair.write(keys, to: directory)
            NSWorkspace.shared.activateFileViewerSelecting([publicURL])

            let alert = NSAlert()
            alert.messageText = "Key pair created"
            alert.informativeText = """
                Host \(KeyPair.publicKeyFilename) so it is reachable at

                https://YOUR-DOMAIN/\(KeyPair.wellKnownPath)

                then enter that domain above and click Register App with \
                Tesla. Keep \(KeyPair.privateKeyFilename) safe — Teslaris \
                never needs it.
                """
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Open Setup Guide")
            if alert.runModal() == .alertSecondButtonReturn,
               let url = URL(string: "https://simonbusborg.github.io/teslaris/#setup") {
                NSWorkspace.shared.open(url)
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't save the key pair"
            alert.informativeText = error.localizedDescription
            alert.runModal()
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
        // New credentials invalidate the old session.
        Keychain.deleteRefreshToken()
        window?.orderOut(nil)
        onSignIn()
    }

    @objc private func cancelAction() {
        window?.orderOut(nil)
    }
}
