import XCTest
@testable import Teslaris
import TeslarisShared

/// App-side formatting: what depends on AppKit or VehicleData. The pure
/// text rules are tested in TeslarisSharedTests; testDistanceFormatting
/// stays here to cover StatusItemController's wrapper over them.
final class FormattingTests: XCTestCase {

    func testDistanceFormatting() {
        XCTAssertEqual(StatusItemController.distance(km: 412, unit: .kilometers), "412 km")
        XCTAssertEqual(StatusItemController.distance(km: 412, unit: .miles), "256 mi")
    }

    func testBatteryColor() {
        XCTAssertEqual(StatusItemController.batteryColor(percentage: 15, charging: true), .systemGreen)
        XCTAssertEqual(StatusItemController.batteryColor(percentage: 15, charging: false), .systemOrange)
        XCTAssertEqual(StatusItemController.batteryColor(percentage: 80, charging: false), .controlAccentColor)
    }

    func testOpenSummary() {
        var data = VehicleData(batteryPercentage: 80, rangeKm: 400, chargingState: "Disconnected",
                               minutesToFull: nil, chargeLimitPercent: nil, chargingPowerKw: nil,
                               vehicleName: nil, vin: nil, odometerKm: nil,
                               isAsleep: false, lastUpdated: Date())
        XCTAssertNil(StatusItemController.openSummary(for: data))

        data.openWindows = 0; data.openDoors = 0
        data.frunkOpen = false; data.trunkOpen = false
        XCTAssertNil(StatusItemController.openSummary(for: data))

        data.openWindows = 1
        XCTAssertEqual(StatusItemController.openSummary(for: data), "A window open")

        data.openWindows = 2; data.trunkOpen = true
        XCTAssertEqual(StatusItemController.openSummary(for: data), "2 windows, trunk open")

        data.openWindows = 0; data.openDoors = 1; data.trunkOpen = false
        XCTAssertEqual(StatusItemController.openSummary(for: data), "A door open")
    }

    /// The bar title can be a bare "0min"; VoiceOver hears words instead.
    func testStatusItemAccessibilityLabel() {
        var data = VehicleData(batteryPercentage: 78.4, rangeKm: 400, chargingState: "Charging",
                               minutesToFull: 40, chargeLimitPercent: nil, chargingPowerKw: nil,
                               vehicleName: nil, vin: nil, odometerKm: nil,
                               isAsleep: false, lastUpdated: Date())
        XCTAssertEqual(StatusItemController.accessibilityLabel(for: nil), "Teslaris")
        XCTAssertEqual(StatusItemController.accessibilityLabel(for: data), "Teslaris, 78%, Charging")
        data.isAsleep = true
        XCTAssertEqual(StatusItemController.accessibilityLabel(for: data),
                       "Teslaris, 78%, Charging, asleep")
    }

    func testMenuBarIcon() {
        func vehicle(state: String, battery: Double) -> VehicleData {
            VehicleData(batteryPercentage: battery, rangeKm: 200, chargingState: state,
                        minutesToFull: nil, chargeLimitPercent: nil, chargingPowerKw: nil,
                        vehicleName: nil, vin: nil, odometerKm: nil,
                        isAsleep: false, lastUpdated: Date())
        }
        XCTAssertEqual(StatusItemController.icon(for: vehicle(state: "Charging", battery: 15)),
                       "bolt.car.fill")
        XCTAssertEqual(StatusItemController.icon(for: vehicle(state: "Stopped", battery: 15)),
                       "bolt.car")
        XCTAssertEqual(StatusItemController.icon(for: vehicle(state: "Disconnected", battery: 15)),
                       "car")
        XCTAssertEqual(StatusItemController.icon(for: vehicle(state: "Disconnected", battery: 80)),
                       "car")
        XCTAssertEqual(StatusItemController.icon(for: nil), "car")
    }
}
