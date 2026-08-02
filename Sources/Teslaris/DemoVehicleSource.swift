//
//  DemoVehicleSource.swift
//  Teslaris
//
//  A scripted VehicleDataSource: plays a full day-in-the-life timeline
//  (parked → plugged in → charging → complete → unplugged → asleep) one
//  step per fetch, so the whole UI can be exercised — and screenshotted
//  honestly — with no Tesla account at all.
//
//  Enable with:  defaults write com.weareheavy.teslaris debug_demo_mode -bool YES
//

import Foundation

final class DemoVehicleSource: VehicleDataSource {

    static var enabled: Bool {
        UserDefaults.standard.bool(forKey: "debug_demo_mode")
    }

    var isAuthenticated: Bool { true }
    let vehicles = [VehicleSummary(vin: "5YJ3E7EB0LF000000", title: "Millennium Falcon")]

    private var step = 0

    func restoreSession() async throws {}

    func fetchVehicleData(vin: String) async throws -> VehicleData {
        defer { step += 1 }
        let timeline: [(state: String, battery: Double, power: Int?, minutes: Int?, asleep: Bool)] = [
            ("Disconnected", 62, nil, nil, false),
            ("Disconnected", 61, nil, nil, false),
            ("Stopped",      61, nil, nil, false),   // plugged in, waiting
            ("Charging",     62, 11, 138, false),
            ("Charging",     68, 11, 102, false),
            ("Charging",     75, 11, 66,  false),
            ("Charging",     84, 11, 30,  false),
            ("Complete",     90, nil, nil, false),
            ("Disconnected", 90, nil, nil, false),
            ("Disconnected", 89, nil, nil, true),    // car went to sleep
        ]
        let entry = timeline[step % timeline.count]

        var data = VehicleData(
            batteryPercentage: entry.battery,
            rangeKm: Int(entry.battery * 5.2),      // ~520 km at 100%
            chargingState: entry.state,
            minutesToFull: entry.minutes,
            chargeLimitPercent: 90,
            chargingPowerKw: entry.power,
            vehicleName: "Millennium Falcon",
            vin: vehicles[0].vin,
            odometerKm: 23_412,
            isAsleep: false,
            lastUpdated: Date()
        )
        // Cabin details so the demo exercises every menu row; Stealth Grey
        // on Nova wheels also shows off the auto-detected car image.
        data.insideTempC = 21
        data.outsideTempC = 14
        data.locked = true
        data.temperatureUnit = "C"
        data.exteriorColor = "StealthGrey"
        data.wheelType = "Nova19"
        return entry.asleep ? data.asAsleep() : data
    }
}
