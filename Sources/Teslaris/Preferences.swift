//
//  Preferences.swift
//  Teslaris
//
//  Non-secret settings live in UserDefaults. The client secret and the
//  OAuth refresh token live in the Keychain (see Keychain.swift).
//

import Foundation
import TeslarisShared

enum DisplayOption: String, CaseIterable {
    case batteryPercentage = "Battery Percentage"
    case range = "Range"
    case chargeTime = "Charge Time"
}

/// How often an awake, parked car is asked for fresh numbers. The raw value
/// is the interval in seconds — what sits in UserDefaults — so a choice can
/// be added without renumbering anything. Charging and a sleeping car keep
/// their own cadence; see AppDelegate.refreshInterval(for:monthlyRequests:).
enum RefreshInterval: Int, CaseIterable {
    case oneMinute = 60
    case twoMinutes = 120
    case fiveMinutes = 300
    case tenMinutes = 600
    case fifteenMinutes = 900

    /// Teslaris polled parked cars every 15 minutes before this was a
    /// choice, so that stays the default: nobody's Fleet API usage goes up
    /// by updating.
    static let `default`: RefreshInterval = .fifteenMinutes

    var title: String {
        self == .oneMinute ? "Every minute" : "Every \(rawValue / 60) minutes"
    }
}

/// Fleet API regional gateways. China needs auth.tesla.cn as well and is
/// not supported yet.
enum Region: String, CaseIterable {
    case northAmerica = "North America, Asia-Pacific"
    case europe = "Europe, Middle East, Africa"

    var apiBase: String {
        switch self {
        case .northAmerica: return "https://fleet-api.prd.na.vn.cloud.tesla.com"
        case .europe: return "https://fleet-api.prd.eu.vn.cloud.tesla.com"
        }
    }
}

enum Preferences {
    private static let d = UserDefaults.standard

    /// The user's own Tesla developer application client ID.
    static var clientId: String {
        get { d.string(forKey: "tesla_client_id") ?? "" }
        set { d.set(newValue, forKey: "tesla_client_id") }
    }

    static var vin: String {
        get { d.string(forKey: "tesla_vin") ?? "" }
        set { d.set(newValue, forKey: "tesla_vin") }
    }

    /// Domain hosting the public key (the app's one-time partner
    /// registration posts it to Tesla). Example: "username.github.io".
    static var domain: String {
        get { d.string(forKey: "tesla_domain") ?? "" }
        set { d.set(newValue, forKey: "tesla_domain") }
    }

    static var region: Region {
        get {
            let raw = d.string(forKey: "tesla_region") ?? ""
            return Region(rawValue: raw) ?? .europe
        }
        set { d.set(newValue.rawValue, forKey: "tesla_region") }
    }

    static var displayOption: DisplayOption {
        get {
            let raw = d.string(forKey: "statusbar_display_option") ?? ""
            return DisplayOption(rawValue: raw) ?? .batteryPercentage
        }
        set { d.set(newValue.rawValue, forKey: "statusbar_display_option") }
    }

    static var distanceUnit: DistanceUnit {
        get {
            let raw = d.string(forKey: "distance_unit") ?? ""
            return DistanceUnit(rawValue: raw) ?? .kilometers
        }
        set { d.set(newValue.rawValue, forKey: "distance_unit") }
    }

    static var refreshInterval: RefreshInterval {
        get { RefreshInterval(rawValue: d.integer(forKey: "refresh_interval")) ?? .default }
        set { d.set(newValue.rawValue, forKey: "refresh_interval") }
    }

    static var launchAtLogin: Bool {
        get { d.bool(forKey: "launch_at_login") }
        set { d.set(newValue, forKey: "launch_at_login") }
    }

    // Notification preferences default to on; only an explicit opt-out
    // (stored false) disables them.
    private static func boolDefaultTrue(_ key: String) -> Bool {
        d.object(forKey: key) == nil ? true : d.bool(forKey: key)
    }

    static var notifyChargingStarted: Bool {
        get { boolDefaultTrue("notify_charging_started") }
        set { d.set(newValue, forKey: "notify_charging_started") }
    }

    static var notifyChargingComplete: Bool {
        get { boolDefaultTrue("notify_charging_complete") }
        set { d.set(newValue, forKey: "notify_charging_complete") }
    }

    static var notifyChargingProblem: Bool {
        get { boolDefaultTrue("notify_charging_problem") }
        set { d.set(newValue, forKey: "notify_charging_problem") }
    }

    static var notifyLowBattery: Bool {
        get { boolDefaultTrue("notify_low_battery") }
        set { d.set(newValue, forKey: "notify_low_battery") }
    }

    /// Only values Settings offers are honoured, so a stray `defaults write`
    /// can't leave the popup with nothing selected.
    static var lowBatteryThreshold: Int {
        get {
            guard let stored = d.object(forKey: "low_battery_threshold") as? Int,
                  LowBatteryWatch.thresholds.contains(stored) else {
                return LowBatteryWatch.defaultThreshold
            }
            return stored
        }
        set { d.set(newValue, forKey: "low_battery_threshold") }
    }

    /// Whether the reminder has already fired for this car's current
    /// discharge. Per VIN, so switching cars can neither swallow nor repeat
    /// a warning, and persisted so a relaunch doesn't warn again.
    static func lowBatteryWarned(vin: String) -> Bool {
        d.bool(forKey: "low_battery_warned_" + vin)
    }

    static func setLowBatteryWarned(_ warned: Bool, vin: String) {
        d.set(warned, forKey: "low_battery_warned_" + vin)
    }
}
