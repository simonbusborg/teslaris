//
//  Notifier.swift
//  Teslaris
//
//  Local notifications for charging milestones, derived by comparing
//  consecutive refreshes, the low-battery reminder, and the tyre-pressure
//  and left-unlocked warnings. UNUserNotificationCenter only works from a real
//  .app bundle, so everything is a no-op under `swift run`.
//

import AppKit
import UserNotifications
import TeslarisShared

final class Notifier: NSObject, UNUserNotificationCenterDelegate {

    private let available = Bundle.main.bundleURL.pathExtension == "app"
    private var authorized = false
    /// The unlocked stretch in progress, per VIN; see UnlockedWatch.State.
    private var unlocked: [String: UnlockedWatch.State] = [:]

    func requestAuthorizationIfNeeded() {
        guard available else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            self?.authorized = granted
        }
    }

    func vehicleDataDidUpdate(old: VehicleData?, new: VehicleData) {
        guard available, authorized else { return }

        // Runs before the `old` guard: a reminder that only fired on a
        // comparison would stay silent through the first refresh after
        // launch, which is exactly when the app is catching up on a car
        // that drained while it wasn't running.
        checkLowBattery(new)
        checkTyres(new)
        checkUnlocked(new)

        guard let old else { return }

        let done = new.chargingState == "Complete" || new.batteryPercentage >= 99.5
        let trouble = new.chargingState == "NoPower"

        if !old.isCharging && new.isCharging {
            guard Preferences.notifyChargingStarted else { return }
            var body = String(format: "%.0f%%", new.batteryPercentage)
            if let minutes = new.minutesToFull, minutes > 0 {
                body += " · full in \(CarFormat.shortDuration(minutes: minutes))"
            }
            post(title: "Charging started", body: body)
        } else if old.isCharging && !new.isCharging && done {
            guard Preferences.notifyChargingComplete else { return }
            post(title: "Charging complete",
                 body: String(format: "%.0f%% · %@ range", new.batteryPercentage,
                              StatusItemController.distance(km: new.rangeKm)))
        } else if old.isCharging && trouble {
            guard Preferences.notifyChargingProblem else { return }
            post(title: "Charging problem",
                 body: String(format: "Charger reported no power at %.0f%%", new.batteryPercentage))
        }
    }

    /// A sleeping car can't lock itself, so one that fell asleep unlocked is
    /// still unlocked — and at the parked pace it is often asleep by the
    /// second reading. Without this the warning would wait for a reading
    /// that never comes.
    func vehicleIsAsleep(cached: VehicleData) {
        guard available, authorized else { return }
        checkUnlocked(cached)
    }

    private func checkTyres(_ new: VehicleData) {
        let vin = new.vin ?? Preferences.vin
        let warned = Preferences.tyreWarned(vin: vin)
        let outcome = TyreWatch.evaluate(lowTyres: new.lowTyres, warned: warned)
        // Tracked with the warning switched off too, as for low battery.
        if outcome.warned != warned {
            Preferences.setTyreWarned(outcome.warned, vin: vin)
        }
        guard outcome.notify, Preferences.notifyTyrePressure else { return }
        post(title: "Low tyre pressure",
             body: TyreWatch.summary(lowTyres: new.lowTyres ?? [],
                                     pressuresBar: new.tyrePressuresBar,
                                     unit: new.tyrePressureUnit))
    }

    private func checkUnlocked(_ new: VehicleData, now: Date = Date()) {
        let vin = new.vin ?? Preferences.vin
        let outcome = UnlockedWatch.evaluate(locked: new.locked,
                                             userPresent: new.userPresent ?? false,
                                             state: unlocked[vin],
                                             now: now)
        unlocked[vin] = outcome.state
        guard outcome.notify, Preferences.notifyUnlocked, let state = outcome.state else { return }
        let minutes = Int((now.timeIntervalSince(state.since) / 60).rounded())
        post(title: "Car left unlocked",
             body: "\(new.vehicleName ?? "Your car") has been unlocked for \(minutes) min")
    }

    private func checkLowBattery(_ new: VehicleData) {
        let vin = new.vin ?? Preferences.vin
        let warned = Preferences.lowBatteryWarned(vin: vin)
        // Plugged in counts as charging here, not only "Charging": a Tesla
        // waiting for scheduled off-peak charging reports "Stopped", and
        // telling that owner to plug in would be wrong. "NoPower" is the
        // exception — the cable is in but nothing is coming through it, so
        // a draining battery still deserves the reminder.
        let pluggedInWithPower = new.isPluggedIn == true && new.chargingState != "NoPower"
        let outcome = LowBatteryWatch.evaluate(percentage: new.batteryPercentage,
                                               isCharging: new.isCharging || pluggedInWithPower,
                                               threshold: Preferences.lowBatteryThreshold,
                                               warned: warned)
        // The armed/disarmed state is tracked even with the reminder switched
        // off, so turning it on mid-drive doesn't fire for a crossing that
        // happened while it was off.
        if outcome.warned != warned {
            Preferences.setLowBatteryWarned(outcome.warned, vin: vin)
        }
        guard outcome.notify, Preferences.notifyLowBattery else { return }
        post(title: "Low battery",
             body: String(format: "%.0f%% left — time to plug in", new.batteryPercentage))
    }

    private func post(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // Menu bar apps count as "foreground"; without this the banner is suppressed.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
