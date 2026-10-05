//
//  TyrePressure.swift
//  Teslaris
//
//  Decides when the low-tyre-pressure notification fires, and what it
//  says. Pure and apart from Notifier for the same reason LowBattery is:
//  Notifier can't run outside a real .app bundle, this can be tested.
//

import Foundation

enum TyreWatch {

    struct Outcome: Equatable {
        let notify: Bool
        /// The warned flag to persist for this car.
        let warned: Bool
    }

    /// Fires once when the car starts flagging a wheel, and re-arms when it
    /// stops flagging all of them. The car's own warning flags are the
    /// trigger rather than a threshold of ours: it knows the recommended
    /// pressure for its wheels and load, and already has the hysteresis
    /// that keeps a tyre on the line from flapping.
    static func evaluate(lowTyres: [Wheel]?, warned: Bool) -> Outcome {
        // No flags in the response — a car that hasn't driven since waking
        // may not have readings yet. Unknown is not "fine": re-arming here
        // would repeat the warning after every sleep.
        guard let lowTyres else { return Outcome(notify: false, warned: warned) }
        if lowTyres.isEmpty { return Outcome(notify: false, warned: false) }
        return Outcome(notify: !warned, warned: true)
    }

    /// The notification body: each flagged wheel, with its pressure when the
    /// car has one. "Front left 2.1 bar · Rear right 2.3 bar".
    static func summary(lowTyres: [Wheel],
                        pressuresBar: [Wheel: Double],
                        unit: String?) -> String {
        lowTyres.map { wheel -> String in
            guard let reading = reading(bar: pressuresBar[wheel], unit: unit) else { return wheel.title }
            return "\(wheel.title) \(reading)"
        }.joined(separator: " · ")
    }

    /// A pressure in the car's own unit — "2.1 bar" or "30 psi" — or nil
    /// when the car has no reading for the wheel.
    static func reading(bar: Double?, unit: String?) -> String? {
        guard let bar else { return nil }
        return unit?.lowercased() == "psi" ? String(format: "%.0f psi", bar * 14.5038)
                                           : String(format: "%.1f bar", bar)
    }
}
