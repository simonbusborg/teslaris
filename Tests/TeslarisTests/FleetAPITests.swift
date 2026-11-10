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
        "locked": false,
        "sentry_mode": true,
        "fd_window": 1,
        "fp_window": 0,
        "rd_window": 1,
        "rp_window": 0,
        "df": 0, "pf": 0, "dr": 0, "pr": 0,
        "ft": 0,
        "rt": 1,
        "is_user_present": false,
        "tpms_pressure_fl": 2.9, "tpms_pressure_fr": 2.875,
        "tpms_pressure_rl": 2.1, "tpms_pressure_rr": null,
        "tpms_soft_warning_fl": false, "tpms_soft_warning_fr": false,
        "tpms_soft_warning_rl": true, "tpms_soft_warning_rr": false,
        "tpms_hard_warning_fl": false, "tpms_hard_warning_fr": false,
        "tpms_hard_warning_rl": false, "tpms_hard_warning_rr": true,
        "software_update": {
          "status": "available",
          "version": "2026.20.6"
        },
        "timestamp": 1692141038419
      },
      "climate_state": {
        "inside_temp": 21.4,
        "outside_temp": 13.6,
        "is_climate_on": false,
        "is_preconditioning": true,
        "timestamp": 1692141038420
      },
      "gui_settings": {
        "gui_distance_units": "km/hr",
        "gui_temperature_units": "C",
        "gui_tirepressure_units": "Bar",
        "timestamp": 1692141038420
      },
      "vehicle_config": {
        "car_type": "model3",
        "exterior_color": "DeepBlue",
        "wheel_type": "Photon18",
        "timestamp": 1692141038420
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

    func testParseCabinAndConfig() {
        let parsed = TeslaFleetAPI.parseVehicleData(fixture(), now: Date())

        XCTAssertEqual(parsed.insideTempC, 21.4)
        XCTAssertEqual(parsed.outsideTempC, 13.6)
        XCTAssertEqual(parsed.isClimateOn, false)
        XCTAssertEqual(parsed.isPreconditioning, true)
        XCTAssertEqual(parsed.locked, false)
        XCTAssertEqual(parsed.sentryMode, true)
        XCTAssertEqual(parsed.openWindows, 2)
        XCTAssertEqual(parsed.openDoors, 0)
        XCTAssertEqual(parsed.frunkOpen, false)
        XCTAssertEqual(parsed.trunkOpen, true)
        XCTAssertEqual(parsed.softwareUpdateStatus, "available")
        XCTAssertEqual(parsed.softwareUpdateVersion, "2026.20.6")
        XCTAssertEqual(parsed.temperatureUnit, "C")
        XCTAssertEqual(parsed.exteriorColor, "DeepBlue")
        XCTAssertEqual(parsed.wheelType, "Photon18")
    }

    func testParseTyresAndPresence() {
        let parsed = TeslaFleetAPI.parseVehicleData(fixture(), now: Date())

        XCTAssertEqual(parsed.userPresent, false)
        // Soft on the rear left, hard on the rear right: both count.
        XCTAssertEqual(parsed.lowTyres, [.rearLeft, .rearRight])
        XCTAssertEqual(parsed.tyrePressuresBar[.frontLeft], 2.9)
        XCTAssertEqual(parsed.tyrePressuresBar[.rearLeft], 2.1)
        XCTAssertNil(parsed.tyrePressuresBar[.rearRight])   // null: no reading yet
        XCTAssertEqual(parsed.tyrePressureUnit, "Bar")
    }

    func testTyreFlagsAbsentMeansUnknown() {
        var vehicle = fixture()
        var state = vehicle["vehicle_state"] as! [String: Any]
        for key in state.keys where key.hasPrefix("tpms_") { state[key] = nil }
        vehicle["vehicle_state"] = state

        let parsed = TeslaFleetAPI.parseVehicleData(vehicle, now: Date())
        XCTAssertNil(parsed.lowTyres)
        XCTAssertTrue(parsed.tyrePressuresBar.isEmpty)
    }

    func testIdleSoftwareUpdateStatusBecomesNil() {
        var json = fixture()
        var state = json["vehicle_state"] as! [String: Any]
        state["software_update"] = ["status": "", "version": ""]
        json["vehicle_state"] = state
        let parsed = TeslaFleetAPI.parseVehicleData(json, now: Date())
        XCTAssertNil(parsed.softwareUpdateStatus)
        XCTAssertNil(parsed.softwareUpdateVersion)
    }

    func testParseHandlesMissingSections() {
        let parsed = TeslaFleetAPI.parseVehicleData(["vin": "X"], now: Date())
        XCTAssertEqual(parsed.batteryPercentage, 0)
        XCTAssertEqual(parsed.chargingState, "Unknown")
        XCTAssertNil(parsed.minutesToFull)
        XCTAssertNil(parsed.isPluggedIn)
        // Absent sections must stay nil — never "0 windows open" invented
        // from a fixture that simply didn't include the fields.
        XCTAssertNil(parsed.insideTempC)
        XCTAssertNil(parsed.locked)
        XCTAssertNil(parsed.openWindows)
        XCTAssertNil(parsed.openDoors)
        XCTAssertNil(parsed.frunkOpen)
        XCTAssertNil(parsed.softwareUpdateStatus)
        XCTAssertNil(parsed.exteriorColor)
        XCTAssertNil(parsed.wheelType)
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
        XCTAssertEqual(asleep.insideTempC, 21.4)
        XCTAssertEqual(asleep.exteriorColor, "DeepBlue")
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
        for _ in 0..<12 {
            let data = try await demo.fetchVehicleData(vin: "")
            if data.isCharging { sawCharging = true }
            if data.isAsleep { sawAsleep = true }
        }
        XCTAssertTrue(sawCharging)
        XCTAssertTrue(sawAsleep)
    }

    /// Demo mode is the only way to see the low-battery reminder without a
    /// car, so the timeline has to cross the default threshold unplugged.
    func testDemoTimelineTriggersLowBatteryReminder() async throws {
        let demo = DemoVehicleSource()
        var warned = false, fired = false
        for _ in 0..<12 {
            let data = try await demo.fetchVehicleData(vin: "")
            let outcome = LowBatteryWatch.evaluate(
                percentage: data.batteryPercentage,
                isCharging: data.isCharging || data.isPluggedIn == true,
                threshold: LowBatteryWatch.defaultThreshold, warned: warned)
            if outcome.notify { fired = true }
            warned = outcome.warned
        }
        XCTAssertTrue(fired)
    }
    // MARK: - Failure mapping

    private func failure(_ status: Int, _ body: String = "") -> TeslarisError {
        TeslaFleetAPI.failure(for: status, body: Data(body.utf8), request: "Vehicle list")
    }

    /// The tester report that prompted this: a 412 used to read only
    /// "vehicles list failed". It must now name the status and the fix.
    func testUnregisteredRegionNamesStatusAndFix() {
        let message = failure(412, #"{"error":"must be registered in the current region"}"#)
            .localizedDescription
        XCTAssertTrue(message.contains("412"))
        XCTAssertTrue(message.contains("Register App with Tesla"))
        XCTAssertTrue(message.contains("must be registered in the current region"))
    }

    func testWrongRegionPointsAtRegionSetting() {
        XCTAssertTrue(failure(421).localizedDescription.contains("Region"))
    }

    /// A rejected token is a sign-out, so the app opens Settings for it.
    func testExpiredTokenCountsAsSignedOut() {
        XCTAssertTrue(AppDelegate.isSignedOut(failure(401)))
        XCTAssertTrue(AppDelegate.isSignedOut(failure(401, #"{"error":"login_required"}"#)))
    }

    /// Remote access switched off in the car is not a sign-in problem —
    /// signing in again would not help.
    func testMobileAccessDisabledIsNotASignOut() {
        let error = failure(401, #"{"error":"mobile_access_disabled"}"#)
        XCTAssertFalse(AppDelegate.isSignedOut(error))
        XCTAssertTrue(error.localizedDescription.contains("Mobile Access"))
    }

    /// Jeppe's 403 read "allow vehicle information ()": Tesla sent an empty
    /// error_description beside the real error, and the empty one won.
    func testEmptyDescriptionDoesNotHideTeslasError() {
        let message = failure(403, #"{"response":null,"error":"Unauthorized missing scopes","error_description":""}"#)
            .localizedDescription
        XCTAssertTrue(message.contains("Unauthorized missing scopes"))
        XCTAssertFalse(message.contains("()"))
    }

    /// A JWT whose payload is `claims`; header and signature don't matter.
    private func jwt(_ claims: String) -> String {
        let payload = Data(claims.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "eyJhbGciOiJSUzI1NiJ9.\(payload).signature"
    }

    func testGrantedScopesFromToken() {
        XCTAssertEqual(TeslaFleetAPI.grantedScopes(accessToken: jwt(#"{"scp":["openid","vehicle_device_data"]}"#)),
                       ["openid", "vehicle_device_data"])
        XCTAssertEqual(TeslaFleetAPI.grantedScopes(accessToken: jwt(#"{"scp":"openid offline_access"}"#)),
                       ["openid", "offline_access"])
        XCTAssertNil(TeslaFleetAPI.grantedScopes(accessToken: jwt(#"{"sub":"x"}"#)))
        XCTAssertNil(TeslaFleetAPI.grantedScopes(accessToken: "not-a-jwt"))
    }

    /// When the token shows vehicle data was never granted, say exactly
    /// that instead of a bare 403.
    func testForbiddenWithoutVehicleScopeNamesTheMissingGrant() {
        let missing = TeslaFleetAPI.failure(for: 403, body: Data(), request: "Vehicle list",
                                            grantedScopes: ["openid", "offline_access"])
        XCTAssertTrue(missing.localizedDescription.contains("didn't grant"))
        let granted = TeslaFleetAPI.failure(for: 403, body: Data(), request: "Vehicle list",
                                            grantedScopes: ["openid", "vehicle_device_data"])
        XCTAssertTrue(granted.localizedDescription.contains("403"))
        XCTAssertFalse(granted.localizedDescription.contains("didn't grant"))
    }

    func testUnknownStatusKeepsTeslasWording() {
        let message = failure(418, #"{"error":"teapot","error_description":"short and stout"}"#)
            .localizedDescription
        XCTAssertTrue(message.contains("418"))
        XCTAssertTrue(message.contains("short and stout"))
    }

    func testNonJSONBodyStillReportsStatus() {
        XCTAssertTrue(failure(502, "<html>Bad Gateway</html>").localizedDescription.contains("502"))
    }
    // MARK: - Wake opt-in

    /// vehicle_cmds also covers unlock and remote start: it must never be
    /// requested unless the owner opted in to waking.
    func testDefaultScopesStayReadOnly() {
        XCTAssertFalse(TeslaFleetAPI.scopes(allowWake: false).contains("vehicle_cmds"))
        XCTAssertTrue(TeslaFleetAPI.scopes(allowWake: true).contains("vehicle_cmds"))
        XCTAssertTrue(TeslaFleetAPI.scopes(allowWake: true).contains("vehicle_device_data"))
    }

    /// A wake waits about a minute at most, in a bounded number of
    /// billed checks, so a car out of coverage can't run up a bill.
    func testWakePollingIsBounded() {
        let delays = TeslaFleetAPI.wakePollDelays
        XCTAssertLessThanOrEqual(delays.count, 10)
        XCTAssertEqual(delays.reduce(0, +), 60, accuracy: 5)
    }
}
