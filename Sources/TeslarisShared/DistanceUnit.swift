//
//  DistanceUnit.swift
//  TeslarisShared
//
//  Lives in the Foundation-only shared target, with the formatting that
//  depends on it, so the rules for turning numbers into menu text can be
//  built and tested without AppKit — on Linux too. Same split as Polaris.
//

import Foundation

/// The raw values are what sits in UserDefaults and double as the Settings
/// titles, so renaming a case's string would silently reset every stored
/// preference to kilometers. Codable because the unit travels to the widget
/// inside the snapshot.
public enum DistanceUnit: String, CaseIterable, Codable {
    case kilometers = "Kilometers (km)"
    case miles = "Miles (mi)"

    public var suffix: String { self == .kilometers ? "km" : "mi" }

    /// Internal canonical unit is km; miles convert at display time.
    public func convert(km: Int) -> Int {
        self == .kilometers ? km : Int((Double(km) * 0.621371).rounded())
    }
}
