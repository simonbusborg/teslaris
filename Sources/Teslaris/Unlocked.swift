//
//  Unlocked.swift
//  Teslaris
//
//  Decides when the "car left unlocked" notification fires. Pure and apart
//  from Notifier, like LowBattery, so it can be tested without a bundle.
//

import Foundation

enum UnlockedWatch {

    /// How long the car has to have been seen unlocked before it counts as
    /// left that way. Someone loading the boot is not a forgotten car.
    static let delay: TimeInterval = 10 * 60

    /// A gap between readings longer than this restarts the clock. The Mac
    /// may have slept through the night while the car was locked and
    /// unlocked again; without this, the first reading after it wakes would
    /// look like an unlocked stretch as long as the gap.
    static let staleAfter: TimeInterval = 2 * 60 * 60

    /// One unlocked stretch. Kept in memory only: after a relaunch the
    /// stretch simply starts over.
    struct State: Equatable {
        var since: Date
        var lastSeen: Date
        var warned: Bool
    }

    struct Outcome: Equatable {
        let notify: Bool
        /// Nil once the car is locked or occupied again.
        let state: State?
    }

    static func evaluate(locked: Bool?,
                         userPresent: Bool,
                         state: State?,
                         now: Date) -> Outcome {
        // The car didn't say — keep whatever was known.
        guard let locked else { return Outcome(notify: false, state: state) }
        if locked || userPresent { return Outcome(notify: false, state: nil) }

        var current = state ?? State(since: now, lastSeen: now, warned: false)
        if now.timeIntervalSince(current.lastSeen) > staleAfter {
            current = State(since: now, lastSeen: now, warned: false)
        }
        current.lastSeen = now

        let overdue = now.timeIntervalSince(current.since) >= delay
        guard overdue, !current.warned else { return Outcome(notify: false, state: current) }
        current.warned = true
        return Outcome(notify: true, state: current)
    }
}
