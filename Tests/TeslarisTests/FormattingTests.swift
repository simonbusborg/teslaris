import XCTest
@testable import Teslaris

final class FormattingTests: XCTestCase {

    func testShortDuration() {
        XCTAssertEqual(StatusItemController.shortDuration(minutes: 45), "45min")
        XCTAssertEqual(StatusItemController.shortDuration(minutes: 60), "1h")
        XCTAssertEqual(StatusItemController.shortDuration(minutes: 135), "2h15m")
    }

    func testVersionComparison() {
        XCTAssertTrue(UpdateChecker.isVersion("2.0.0", newerThan: "1.9.9"))
        XCTAssertTrue(UpdateChecker.isVersion("1.10.0", newerThan: "1.9.1"))
        XCTAssertFalse(UpdateChecker.isVersion("1.0.0", newerThan: "1.0.0"))
    }

    func testDistanceUnitConversion() {
        XCTAssertEqual(DistanceUnit.kilometers.convert(km: 412), 412)
        XCTAssertEqual(DistanceUnit.miles.convert(km: 412), 256)
    }

    func testDistanceFormatting() {
        XCTAssertEqual(StatusItemController.distance(km: 412, unit: .kilometers), "412 km")
        XCTAssertEqual(StatusItemController.distance(km: 412, unit: .miles), "256 mi")
    }

    func testHumanStatus() {
        XCTAssertEqual(StatusItemController.humanStatus("Charging"), "Charging")
        XCTAssertEqual(StatusItemController.humanStatus("Complete"), "Charged")
        XCTAssertEqual(StatusItemController.humanStatus("Disconnected"), "Not plugged in")
        XCTAssertEqual(StatusItemController.humanStatus("Stopped"), "Plugged in")
        XCTAssertEqual(StatusItemController.humanStatus("FutureState"), "FutureState")
    }

    func testBatteryColor() {
        XCTAssertEqual(StatusItemController.batteryColor(percentage: 15, charging: true), .systemGreen)
        XCTAssertEqual(StatusItemController.batteryColor(percentage: 15, charging: false), .systemOrange)
        XCTAssertEqual(StatusItemController.batteryColor(percentage: 80, charging: false), .controlAccentColor)
    }

    func testTemperatureFollowsCarUnit() {
        XCTAssertEqual(StatusItemController.temperature(celsius: 21.4, unit: "C"), "21°C")
        XCTAssertEqual(StatusItemController.temperature(celsius: 21.4, unit: nil), "21°C")
        XCTAssertEqual(StatusItemController.temperature(celsius: 21.4, unit: "F"), "71°F")
        XCTAssertEqual(StatusItemController.temperature(celsius: -0.4, unit: "C"), "0°C")
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

    func testSoftwareUpdateLabel() {
        XCTAssertNil(StatusItemController.softwareUpdateLabel(status: nil, version: nil))
        XCTAssertEqual(StatusItemController.softwareUpdateLabel(status: "available",
                                                                version: "2026.20.6"),
                       "Update 2026.20.6 available")
        XCTAssertEqual(StatusItemController.softwareUpdateLabel(status: "installing", version: nil),
                       "Update installing")
        XCTAssertEqual(StatusItemController.softwareUpdateLabel(status: "downloading_wifi_wait",
                                                                version: "2026.20.6"),
                       "Update 2026.20.6 downloading")
    }

    func testMenuBarIcon() {
        func vehicle(state: String, battery: Double) -> VehicleData {
            VehicleData(batteryPercentage: battery, rangeKm: 200, chargingState: state,
                        minutesToFull: nil, chargeLimitPercent: nil, chargingPowerKw: nil,
                        vehicleName: nil, vin: nil, odometerKm: nil,
                        isAsleep: false, lastUpdated: Date())
        }
        var icon = StatusItemController.icon(for: vehicle(state: "Charging", battery: 15))
        XCTAssertEqual(icon.symbol, "bolt.car.fill"); XCTAssertEqual(icon.tint, .systemGreen)
        icon = StatusItemController.icon(for: vehicle(state: "Stopped", battery: 15))
        XCTAssertEqual(icon.symbol, "bolt.car"); XCTAssertNil(icon.tint)
        icon = StatusItemController.icon(for: vehicle(state: "Disconnected", battery: 15))
        XCTAssertEqual(icon.symbol, "car"); XCTAssertEqual(icon.tint, .systemOrange)
        icon = StatusItemController.icon(for: vehicle(state: "Disconnected", battery: 80))
        XCTAssertEqual(icon.symbol, "car"); XCTAssertNil(icon.tint)
        icon = StatusItemController.icon(for: nil)
        XCTAssertEqual(icon.symbol, "car"); XCTAssertNil(icon.tint)
    }
}
