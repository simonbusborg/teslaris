//
//  CarFormat.swift
//  TeslarisShared
//
//  The text formatting behind the menu and the notifications. None of it
//  needs AppKit, and keeping it out of the app target is what lets it be
//  tested anywhere. StatusItemController keeps thin wrappers over these so
//  its own call sites (and their tests) stay as they were.
//

import Foundation

public enum CarFormat {

    /// Tesla charging_state → human label.
    public static func humanStatus(_ state: String) -> String {
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

    /// "21°C" — or "70°F" when the car itself is set to Fahrenheit
    /// (gui_settings), so the menu always matches the car's screen.
    public static func temperature(celsius: Double, unit: String?) -> String {
        if unit == "F" { return "\(Int((celsius * 9 / 5 + 32).rounded()))°F" }
        return "\(Int(celsius.rounded()))°C"
    }

    /// vehicle_state.software_update → menu label; nil when idle.
    public static func softwareUpdateLabel(status: String?, version: String?) -> String? {
        guard let status, !status.isEmpty else { return nil }
        let v = version.map { " \($0)" } ?? ""
        switch status {
        case "available": return "Update\(v) available"
        case "scheduled": return "Update\(v) scheduled"
        case "downloading", "downloading_wifi_wait": return "Update\(v) downloading"
        case "installing": return "Update\(v) installing"
        default: return "Update\(v) — \(status)"
        }
    }

    public static func shortDuration(minutes: Int) -> String {
        if minutes < 60 { return "\(minutes)min" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h)h" : "\(h)h\(m)m"
    }

    /// "412 km" / "256 mi"; `grouped` adds thousands separators (odometer).
    /// The unit is a parameter rather than read from preferences: this
    /// target has no business knowing where settings are stored.
    public static func distance(km: Int, grouped: Bool = false,
                                unit: DistanceUnit) -> String {
        let value = unit.convert(km: km)
        if grouped {
            let f = NumberFormatter(); f.numberStyle = .decimal
            return "\(f.string(from: NSNumber(value: value)) ?? "\(value)") \(unit.suffix)"
        }
        return "\(value) \(unit.suffix)"
    }
}
