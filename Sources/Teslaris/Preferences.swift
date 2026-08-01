//
//  Preferences.swift
//  Teslaris
//
//  Non-secret settings live in UserDefaults. The client secret and the
//  OAuth refresh token live in the Keychain (see Keychain.swift).
//

import Foundation

enum DisplayOption: String, CaseIterable {
    case batteryPercentage = "Battery Percentage"
    case range = "Range"
    case chargeTime = "Charge Time"
}

enum DistanceUnit: String, CaseIterable {
    case kilometers = "Kilometers (km)"
    case miles = "Miles (mi)"

    var suffix: String { self == .kilometers ? "km" : "mi" }

    /// Internal canonical unit is km; miles convert at display time.
    func convert(km: Int) -> Int {
        self == .kilometers ? km : Int((Double(km) * 0.621371).rounded())
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
}
