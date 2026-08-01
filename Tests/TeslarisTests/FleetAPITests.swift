//
//  FleetAPITests.swift
//  Built against the documented Fleet API response shapes — the whole
//  point of the fixture layer is that Teslaris is testable without a
//  Tesla account or car.
//

import XCTest
@testable import Teslaris

final class FleetAPITests: XCTestCase {

    /// Trimmed from the vehicle_data example on developer.tesla.com.
    private let vehicleDataFixture = """
    {
      "id": 100021,
      "vin": "5YJ3E1EA1NF000000",
      "display_name": "Nikola 2.0",
      "state": "online",
      "charge_state": {
        "battery_level": 42,
        "battery_range": 133.99,
        "charging_state": "Charging",
        "charge_limit_soc": 90,
        "charger_power": 11,
        "minutes_to_full_charge": 138,
        "timestamp": 1692141038420
      },
      "vehicle_state": {
        "odometer": 15720.074889,
        "vehicle_name": "Nikola 2.0",
        "timestamp": 1692141038419
      }
    }
    """

    private func fixture() -> [String: Any] {
        let data = vehicleDataFixture.data(using: .utf8)!
        return (try! JSONSerialization.jsonObject(with: data)) as! [String: Any]
    }

    func testParseVehicleData() {
        let now = Date()
        let parsed = TeslaFleetAPI.parseVehicleData(fixture(), now: now)

        XCTAssertEqual(parsed.batteryPercentage, 42)
        XCTAssertEqual(parsed.rangeKm, 216)            // 133.99 mi
        XCTAssertEqual(parsed.chargingState, "Charging")
        XCTAssertEqual(parsed.minutesToFull, 138)
        XCTAssertEqual(parsed.chargeLimitPercent, 90)
        XCTAssertEqual(parsed.chargingPowerKw, 11)
        XCTAssertEqual(parsed.vehicleName, "Nikola 2.0")
        XCTAssertEqual(parsed.vin, "5YJ3E1EA1NF000000")
        XCTAssertEqual(parsed.odometerKm, 25299)       // 15720.07 mi
        XCTAssertTrue(parsed.isCharging)
        XCTAssertEqual(parsed.isPluggedIn, true)
        XCTAssertFalse(parsed.isAsleep)
        XCTAssertEqual(parsed.lastUpdated, now)
    }

    func testParseHandlesMissingSections() {
        let parsed = TeslaFleetAPI.parseVehicleData(["vin": "X"], now: Date())
        XCTAssertEqual(parsed.batteryPercentage, 0)
        XCTAssertEqual(parsed.chargingState, "Unknown")
        XCTAssertNil(parsed.minutesToFull)
        XCTAssertNil(parsed.isPluggedIn)
    }

    func testZeroMinutesToFullBecomesNil() {
        var json = fixture()
        var charge = json["charge_state"] as! [String: Any]
        charge["minutes_to_full_charge"] = 0
        json["charge_state"] = charge
        XCTAssertNil(TeslaFleetAPI.parseVehicleData(json, now: Date()).minutesToFull)
    }

    func testPluggedInMapping() {
        func data(_ state: String) -> VehicleData {
            var json = fixture()
            var charge = json["charge_state"] as! [String: Any]
            charge["charging_state"] = state
            json["charge_state"] = charge
            return TeslaFleetAPI.parseVehicleData(json, now: Date())
        }
        XCTAssertEqual(data("Charging").isPluggedIn, true)
        XCTAssertEqual(data("Complete").isPluggedIn, true)
        XCTAssertEqual(data("Stopped").isPluggedIn, true)
        XCTAssertEqual(data("NoPower").isPluggedIn, true)
        XCTAssertEqual(data("Disconnected").isPluggedIn, false)
        XCTAssertNil(data("SomethingNew").isPluggedIn)
        XCTAssertFalse(data("Complete").isCharging)
        XCTAssertTrue(data("Starting").isCharging)
    }

    func testAsAsleepKeepsNumbers() {
        let asleep = TeslaFleetAPI.parseVehicleData(fixture(), now: Date()).asAsleep()
        XCTAssertTrue(asleep.isAsleep)
        XCTAssertEqual(asleep.batteryPercentage, 42)
        XCTAssertEqual(asleep.rangeKm, 216)
    }

    // MARK: - OAuth callback parsing

    func testCallbackParsing() {
        let ok = TeslaFleetAPI.parseCallback(
            request: "GET /callback?code=abc123&state=S1 HTTP/1.1\r\nHost: localhost\r\n\r\n",
            expectedState: "S1")
        if case .success(let code)? = ok { XCTAssertEqual(code, "abc123") }
        else { XCTFail("expected success, got \(String(describing: ok))") }
    }

    func testCallbackStateMismatchFails() {
        let result = TeslaFleetAPI.parseCallback(
            request: "GET /callback?code=abc&state=WRONG HTTP/1.1\r\n\r\n",
            expectedState: "S1")
        if case .failure? = result {} else { XCTFail("state mismatch must fail") }
    }

    func testCallbackErrorParameterFails() {
        let result = TeslaFleetAPI.parseCallback(
            request: "GET /callback?error=access_denied&state=S1 HTTP/1.1\r\n\r\n",
            expectedState: "S1")
        if case .failure? = result {} else { XCTFail("error param must fail") }
    }

    func testUnrelatedRequestsAreIgnored() {
        XCTAssertNil(TeslaFleetAPI.parseCallback(
            request: "GET /favicon.ico HTTP/1.1\r\n\r\n", expectedState: "S1"))
        XCTAssertNil(TeslaFleetAPI.parseCallback(
            request: "POST /callback HTTP/1.1\r\n\r\n", expectedState: "S1"))
    }

    func testFormEncoding() {
        let encoded = TeslaFleetAPI.formEncode(["a": "x y", "b": "https://t.co/?q=1"])
        XCTAssertEqual(encoded, "a=x%20y&b=https%3A%2F%2Ft.co%2F%3Fq%3D1")
    }

    // MARK: - Demo source

    func testDemoTimelineReachesChargingAndSleep() async throws {
        let demo = DemoVehicleSource()
        var sawCharging = false, sawAsleep = false
        for _ in 0..<10 {
            let data = try await demo.fetchVehicleData(vin: "")
            if data.isCharging { sawCharging = true }
            if data.isAsleep { sawAsleep = true }
        }
        XCTAssertTrue(sawCharging)
        XCTAssertTrue(sawAsleep)
    }
}
