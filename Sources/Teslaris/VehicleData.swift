//
//  VehicleData.swift
//  Teslaris
//
//  The app-facing vehicle model plus the source protocol every backend
//  implements: the real Fleet API client, the scripted demo source, and
//  test stubs. Unlike Polaris (where we could always test against a real
//  car), Teslaris is built to run fully without one.
//

import Foundation

/// Distances are canonically km here (UI converts per preference), even
/// though the Fleet API reports miles — one conversion at the parse edge.
struct VehicleData {
    let batteryPercentage: Double
    let rangeKm: Int
    /// Tesla charging_state verbatim: "Charging", "Complete", "Disconnected",
    /// "Stopped", "NoPower", "Starting" — or our synthetic "Asleep".
    let chargingState: String
    let minutesToFull: Int?
    let chargeLimitPercent: Int?
    /// Charger power in kW as reported (AC or DC).
    let chargingPowerKw: Int?
    let vehicleName: String?
    let vin: String?
    let odometerKm: Int?
    /// True when this is cached data because the car is asleep.
    let isAsleep: Bool
    let lastUpdated: Date

    var isCharging: Bool { chargingState == "Charging" || chargingState == "Starting" }

    var isPluggedIn: Bool? {
        switch chargingState {
        case "Charging", "Starting", "Complete", "Stopped", "NoPower": return true
        case "Disconnected": return false
        default: return nil
        }
    }

    /// Returns a copy flagged as stale/asleep, keeping the numbers.
    func asAsleep() -> VehicleData {
        VehicleData(batteryPercentage: batteryPercentage, rangeKm: rangeKm,
                    chargingState: chargingState, minutesToFull: minutesToFull,
                    chargeLimitPercent: chargeLimitPercent, chargingPowerKw: chargingPowerKw,
                    vehicleName: vehicleName, vin: vin, odometerKm: odometerKm,
                    isAsleep: true, lastUpdated: lastUpdated)
    }
}

/// One vehicle on the account, for the menu's switcher.
struct VehicleSummary: Equatable {
    let vin: String
    let title: String   // display name, falling back to the model
}

enum TeslarisError: Error, LocalizedError {
    case http(String)
    case parse(String)
    case notConfigured
    case authenticationFailed(String)
    /// Fleet API returns 408 for a sleeping vehicle. Never wake it —
    /// wakes cost money and drain the battery.
    case vehicleAsleep

    var errorDescription: String? {
        switch self {
        case .http(let m): return "HTTP error: \(m)"
        case .parse(let m): return "Parse error: \(m)"
        case .notConfigured: return "Not configured — open Settings"
        case .authenticationFailed(let m): return "Sign-in failed: \(m)"
        case .vehicleAsleep: return "Vehicle is asleep"
        }
    }
}

protocol VehicleDataSource: AnyObject {
    var isAuthenticated: Bool { get }
    /// Vehicles on the account; populated after the first successful fetch.
    var vehicles: [VehicleSummary] { get }
    /// Restore a persisted session (refresh token). Throws when there is none.
    func restoreSession() async throws
    func fetchVehicleData(vin: String) async throws -> VehicleData
}
