import XCTest
import TeslarisShared

final class CarFormatTests: XCTestCase {

    func testShortDuration() {
        XCTAssertEqual(CarFormat.shortDuration(minutes: 45), "45min")
        XCTAssertEqual(CarFormat.shortDuration(minutes: 60), "1h")
        XCTAssertEqual(CarFormat.shortDuration(minutes: 135), "2h15m")
    }

    func testDistanceUnitConversion() {
        XCTAssertEqual(DistanceUnit.kilometers.convert(km: 412), 412)
        XCTAssertEqual(DistanceUnit.miles.convert(km: 412), 256)
    }

    /// The raw values are stored in UserDefaults; changing one resets
    /// everyone's preference.
    func testDistanceUnitRawValuesAreStable() {
        XCTAssertEqual(DistanceUnit(rawValue: "Kilometers (km)"), .kilometers)
        XCTAssertEqual(DistanceUnit(rawValue: "Miles (mi)"), .miles)
    }

    func testDistanceFormatting() {
        XCTAssertEqual(CarFormat.distance(km: 412, unit: .kilometers), "412 km")
        XCTAssertEqual(CarFormat.distance(km: 412, unit: .miles), "256 mi")
    }

    func testHumanStatus() {
        XCTAssertEqual(CarFormat.humanStatus("Charging"), "Charging")
        XCTAssertEqual(CarFormat.humanStatus("Complete"), "Charged")
        XCTAssertEqual(CarFormat.humanStatus("Disconnected"), "Not plugged in")
        XCTAssertEqual(CarFormat.humanStatus("Stopped"), "Plugged in")
        XCTAssertEqual(CarFormat.humanStatus("FutureState"), "FutureState")
    }

    func testTemperatureFollowsCarUnit() {
        XCTAssertEqual(CarFormat.temperature(celsius: 21.4, unit: "C"), "21°C")
        XCTAssertEqual(CarFormat.temperature(celsius: 21.4, unit: nil), "21°C")
        XCTAssertEqual(CarFormat.temperature(celsius: 21.4, unit: "F"), "71°F")
        XCTAssertEqual(CarFormat.temperature(celsius: -0.4, unit: "C"), "0°C")
    }

    func testSoftwareUpdateLabel() {
        XCTAssertNil(CarFormat.softwareUpdateLabel(status: nil, version: nil))
        XCTAssertNil(CarFormat.softwareUpdateLabel(status: "", version: "2026.20.6"))
        XCTAssertEqual(CarFormat.softwareUpdateLabel(status: "available", version: "2026.20.6"),
                       "Update 2026.20.6 available")
        XCTAssertEqual(CarFormat.softwareUpdateLabel(status: "installing", version: nil),
                       "Update installing")
    }
}
