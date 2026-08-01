//
//  StatusItemController.swift
//  Teslaris
//
//  Owns the NSStatusItem and its menu. Everything is a plain NSMenu —
//  no window, no view hierarchy kept alive between clicks.
//  Ported from Polaris; the row/bar building blocks are identical.
//

import AppKit

final class StatusItemController {

    private let statusItem: NSStatusItem
    private let onRefresh: () -> Void
    private let onSettings: () -> Void

    /// Set when a newer release exists; renders as a menu item.
    var updateVersion: String?

    /// Vehicles on the account; more than one adds a Switch Car submenu.
    var vehicles: [VehicleSummary] = []
    var activeVin: String?
    var onSelectVehicle: ((String) -> Void)?

    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    private let carImages = CarImageLoader()
    /// Last render arguments, replayed when a car image arrives late.
    private var lastRender: (data: VehicleData?, error: String?, authenticated: Bool)?

    init(onRefresh: @escaping () -> Void, onSettings: @escaping () -> Void) {
        self.onRefresh = onRefresh
        self.onSettings = onSettings
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "car", accessibilityDescription: "Teslaris")
            button.imagePosition = .imageLeft
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        }

        carImages.onLoad = { [weak self] in
            guard let self, let last = self.lastRender else { return }
            self.render(data: last.data, error: last.error, authenticated: last.authenticated)
        }
    }

    // MARK: - Rendering

    func showLoading() {
        statusItem.button?.title = " …"
    }

    func render(data: VehicleData?, error: String?, authenticated: Bool) {
        lastRender = (data, error, authenticated)
        let (symbol, tint) = Self.icon(for: data)
        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Teslaris")
        statusItem.button?.contentTintColor = tint
        statusItem.button?.title = " " + barTitle(for: data)
        statusItem.menu = buildMenu(data: data, error: error)
    }

    /// Menu bar icon by car state: green bolted car while charging, bolted
    /// car when plugged in but not charging, plain car when unplugged —
    /// orange if the battery is low on top of that.
    static func icon(for data: VehicleData?) -> (symbol: String, tint: NSColor?) {
        guard let data else { return ("car", nil) }
        if data.isCharging { return ("bolt.car.fill", .systemGreen) }
        if data.isPluggedIn == true { return ("bolt.car", nil) }
        if data.batteryPercentage <= 20 { return ("car", .systemOrange) }
        return ("car", nil)
    }

    private func barTitle(for data: VehicleData?) -> String {
        guard let data else { return "--" }
        switch Preferences.displayOption {
        case .batteryPercentage:
            return String(format: "%.0f%%", data.batteryPercentage)
        case .range:
            let unit = Preferences.distanceUnit
            return "\(unit.convert(km: data.rangeKm))\(unit.suffix)"
        case .chargeTime:
            guard data.isCharging, let minutes = data.minutesToFull, minutes > 0 else {
                return "0min"
            }
            return Self.shortDuration(minutes: minutes)
        }
    }

    private func buildMenu(data: VehicleData?, error: String?) -> NSMenu {
        let menu = NSMenu()

        if let data {
            if let vin = data.vin, let image = carImages.image(for: vin) {
                let item = NSMenuItem()
                item.view = CarImageRowView(image: image)
                menu.addItem(item)
            }

            // Identity
            if let name = data.vehicleName, !name.isEmpty {
                menu.addItem(rowItem(name, bold: true))
            }
            if let vin = data.vin, !vin.isEmpty {
                menu.addItem(kvItem("VIN", vin, copyable: true))
            }
            if vehicles.count > 1 {
                let switcher = NSMenuItem(title: "Switch Car", action: nil, keyEquivalent: "")
                let submenu = NSMenu()
                for vehicle in vehicles {
                    let item = NSMenuItem(title: vehicle.title,
                                          action: #selector(selectVehicleAction(_:)),
                                          keyEquivalent: "")
                    item.target = self
                    item.representedObject = vehicle.vin
                    item.state = (vehicle.vin == activeVin) ? .on : .off
                    submenu.addItem(item)
                }
                switcher.submenu = submenu
                menu.addItem(switcher)
            }

            menu.addItem(.separator())

            // Live data
            menu.addItem(kvItem("Battery", String(format: "%.0f%%", data.batteryPercentage)))
            let barItem = NSMenuItem()
            barItem.view = BatteryBarView(
                fraction: data.batteryPercentage / 100,
                color: Self.batteryColor(percentage: data.batteryPercentage, charging: data.isCharging)
            )
            menu.addItem(barItem)
            menu.addItem(kvItem("Range", Self.distance(km: data.rangeKm)))
            menu.addItem(kvItem("Status", Self.humanStatus(data.chargingState)))
            if let plugged = data.isPluggedIn, !data.isCharging {
                menu.addItem(kvItem("Charger", plugged ? "Connected" : "Disconnected"))
            }
            if data.isCharging, let kw = data.chargingPowerKw, kw > 0 {
                menu.addItem(kvItem("Power", "\(kw) kW"))
            }
            if let limit = data.chargeLimitPercent {
                menu.addItem(kvItem("Charge limit", "\(limit)%"))
            }
            if data.isCharging, let minutes = data.minutesToFull, minutes > 0 {
                let fullAt = data.lastUpdated.addingTimeInterval(TimeInterval(minutes * 60))
                menu.addItem(kvItem("Full in",
                                    "\(Self.shortDuration(minutes: minutes)) · \(timeFormatter.string(from: fullAt))"))
            }

            if let km = data.odometerKm {
                menu.addItem(.separator())
                menu.addItem(kvItem("Odometer", Self.distance(km: km, grouped: true)))
            }

            menu.addItem(.separator())
            menu.addItem(kvItem("Updated", timeFormatter.string(from: data.lastUpdated)))
            if data.isAsleep {
                menu.addItem(rowItem("Car is asleep — showing last known data", warning: false))
            }
        } else {
            menu.addItem(Self.infoItem("No data yet"))
        }

        if let error {
            menu.addItem(.separator())
            menu.addItem(Self.infoItem("⚠︎ \(error)"))
        }

        menu.addItem(.separator())

        if let updateVersion {
            let update = NSMenuItem(title: "Update Available (v\(updateVersion))…",
                                    action: #selector(updateAction), keyEquivalent: "")
            update.target = self
            menu.addItem(update)
        }

        let refresh = NSMenuItem(title: "Refresh Now", action: #selector(refreshAction), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)

        let settings = NSMenuItem(title: "Settings…", action: #selector(settingsAction), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Teslaris", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        return menu
    }

    // MARK: - Actions

    @objc private func refreshAction() { onRefresh() }
    @objc private func settingsAction() { onSettings() }
    @objc private func selectVehicleAction(_ sender: NSMenuItem) {
        guard let vin = sender.representedObject as? String, vin != activeVin else { return }
        onSelectVehicle?(vin)
    }
    @objc private func updateAction() { NSWorkspace.shared.open(UpdateChecker.releasesPage) }

    // MARK: - Key/value rows

    /// Total row width, shared with the battery bar.
    static let rowWidth: CGFloat = 308

    private func kvItem(_ key: String, _ value: String, copyable: Bool = false,
                        valueWarning: Bool = false) -> NSMenuItem {
        let item = NSMenuItem()
        item.view = KVRowView(key: key, value: value, valueWarning: valueWarning,
                              copyText: copyable ? value : nil)
        if copyable { item.toolTip = "Click to copy" }
        return item
    }

    private func rowItem(_ text: String, bold: Bool = false, warning: Bool = false) -> NSMenuItem {
        let item = NSMenuItem()
        item.view = KVRowView(key: text, value: nil, bold: bold, warning: warning)
        return item
    }

    // MARK: - Helpers

    private static func infoItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    /// Tesla charging_state → human label.
    static func humanStatus(_ state: String) -> String {
        switch state {
        case "Charging": return "Charging"
        case "Complete": return "Charged"
        case "Disconnected": return "Not plugged in"
        case "Stopped": return "Plugged in"
        case "NoPower": return "Charger has no power"
        case "Starting": return "Starting charge"
        default: return state
        }
    }

    static func shortDuration(minutes: Int) -> String {
        if minutes < 60 { return "\(minutes)min" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h)h" : "\(h)h\(m)m"
    }

    /// "412 km" / "256 mi"; `grouped` adds thousands separators (odometer).
    static func distance(km: Int, grouped: Bool = false,
                         unit: DistanceUnit = Preferences.distanceUnit) -> String {
        let value = unit.convert(km: km)
        if grouped {
            let f = NumberFormatter(); f.numberStyle = .decimal
            return "\(f.string(from: NSNumber(value: value)) ?? "\(value)") \(unit.suffix)"
        }
        return "\(value) \(unit.suffix)"
    }

    static func batteryColor(percentage: Double, charging: Bool) -> NSColor {
        if charging { return .systemGreen }
        if percentage <= 20 { return .systemOrange }
        return .controlAccentColor
    }
}

/// A menu row rendered as a custom view: key on the left, value right-aligned,
/// consistent colors regardless of enabled state, fixed width. Rows with
/// `copyText` highlight on hover and copy on click. (Identical to Polaris.)
final class KVRowView: NSView {

    private let copyText: String?
    private static let sidePad: CGFloat = 14

    init(key: String, value: String?, bold: Bool = false, warning: Bool = false,
         valueWarning: Bool = false, copyText: String? = nil) {
        self.copyText = copyText
        let height: CGFloat = bold ? 26 : 24
        super.init(frame: NSRect(x: 0, y: 0, width: StatusItemController.rowWidth, height: height))
        wantsLayer = true
        layer?.cornerRadius = 4

        let keyLabel = NSTextField(labelWithString: key)
        keyLabel.font = bold ? .boldSystemFont(ofSize: 13) : .systemFont(ofSize: 13)
        keyLabel.textColor = warning ? .systemOrange : (value == nil ? .labelColor : .secondaryLabelColor)
        keyLabel.sizeToFit()
        keyLabel.frame.origin = NSPoint(x: Self.sidePad,
                                        y: (height - keyLabel.frame.height) / 2)
        addSubview(keyLabel)

        if let value {
            let valueLabel = NSTextField(labelWithString: value)
            valueLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
            valueLabel.textColor = valueWarning ? .systemOrange : .labelColor
            valueLabel.alignment = .right
            valueLabel.sizeToFit()
            let maxWidth = StatusItemController.rowWidth - Self.sidePad * 2
                - keyLabel.frame.width - 12
            if valueLabel.frame.width > maxWidth {
                valueLabel.lineBreakMode = .byTruncatingTail
                valueLabel.frame.size.width = maxWidth
                toolTip = value
            }
            valueLabel.frame.origin = NSPoint(
                x: StatusItemController.rowWidth - Self.sidePad - valueLabel.frame.width,
                y: (height - valueLabel.frame.height) / 2
            )
            addSubview(valueLabel)
        }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        if copyText != nil {
            addTrackingArea(NSTrackingArea(rect: bounds,
                                           options: [.mouseEnteredAndExited, .activeAlways],
                                           owner: self, userInfo: nil))
        }
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.09).cgColor
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = nil
    }

    override func mouseUp(with event: NSEvent) {
        guard let copyText else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(copyText, forType: .string)
        enclosingMenuItem?.menu?.cancelTracking()
    }
}

/// Slim battery-level bar shown under the Battery row. Layer-backed;
/// colors resolve via effectiveAppearance. (Identical to Polaris.)
final class BatteryBarView: NSView {

    private let color: NSColor
    private let trackLayer = CALayer()
    private let fillLayer = CALayer()

    init(fraction: Double, color: NSColor) {
        self.color = color
        let height: CGFloat = 13
        let sidePad: CGFloat = 14
        let barHeight: CGFloat = 5
        super.init(frame: NSRect(x: 0, y: 0, width: StatusItemController.rowWidth, height: height))
        wantsLayer = true

        let track = CGRect(x: sidePad, y: (height - barHeight) / 2,
                           width: StatusItemController.rowWidth - sidePad * 2, height: barHeight)
        trackLayer.frame = track
        trackLayer.cornerRadius = barHeight / 2
        layer?.addSublayer(trackLayer)

        let clamped = CGFloat(min(max(fraction, 0), 1))
        var fill = track
        // Never narrower than the endcap radius, or the rounding inverts.
        fill.size.width = clamped > 0 ? max(track.width * clamped, barHeight) : 0
        fillLayer.frame = fill
        fillLayer.cornerRadius = barHeight / 2
        layer?.addSublayer(fillLayer)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            trackLayer.backgroundColor = NSColor.labelColor.withAlphaComponent(0.12).cgColor
            fillLayer.backgroundColor = color.cgColor
        }
    }
}
