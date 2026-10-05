//
//  WidgetSnapshotTests.swift
//  TeslarisSharedTests
//
//  The snapshot is a file format shared by two processes, which makes it the
//  one place where a silent change breaks something nobody is looking at:
//  the app keeps working perfectly while the widget quietly shows nothing.
//

import XCTest
import TeslarisShared

final class WidgetSnapshotTests: XCTestCase {

    private func snapshot(battery: Double = 78, state: String = "Disconnected",
                          asleep: Bool = false,
                          unit: DistanceUnit = .kilometers,
                          written: Date = Date(timeIntervalSince1970: 1_700_000_000)) -> WidgetSnapshot {
        WidgetSnapshot(batteryPercentage: battery, rangeKm: 412, chargingState: state,
                       isAsleep: asleep, fullInMinutes: nil, chargingPowerKw: nil,
                       carTitle: "Millennium Falcon", modelName: "Tesla Model 3",
                       odometerKm: 23412, writtenAt: written, unit: unit, hasImage: false)
    }

    /// A car that reports none of the cabin fields writes a file without
    /// them, and a widget that refused it would go blank.
    func testDecodesASnapshotWithoutTheOptionalFields() throws {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        var json = try JSONSerialization.jsonObject(with: encoder.encode(snapshot())) as! [String: Any]
        for key in ["chargeLimitPercent", "doorsLocked", "openText", "climateText"] {
            json.removeValue(forKey: key)
        }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let thin = try decoder.decode(WidgetSnapshot.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(thin.chargeLimitPercent)
        XCTAssertNil(thin.doorsText)
        XCTAssertNil(thin.attentionText)
    }

    func testAttentionPrefersClimateThenOpeningsThenUnlocked() {
        var s = snapshot()
        XCTAssertNil(s.attentionText)
        s.doorsLocked = false
        XCTAssertEqual(s.attentionText, "Unlocked")
        s.openText = "A window, trunk open"
        XCTAssertEqual(s.attentionText, "A window, trunk open")
        XCTAssertEqual(s.doorsText, "A window, trunk open")
        s.climateText = "Preconditioning"
        XCTAssertEqual(s.attentionText, "Preconditioning")
        s.openText = nil; s.climateText = nil; s.doorsLocked = true
        XCTAssertEqual(s.doorsText, "Locked")
        XCTAssertNil(s.attentionText)
    }

    func testSurvivesARoundTrip() throws {
        let original = snapshot(unit: .miles)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(WidgetSnapshot.self,
                                          from: encoder.encode(original))
        XCTAssertEqual(restored, original)
    }

    /// A poll that changed nothing must not cost a widget reload, but a poll
    /// that moved the battery must.
    func testSameDataIgnoresOnlyTheWriteTime() {
        let first = snapshot()
        let later = snapshot(written: Date(timeIntervalSince1970: 1_700_003_600))
        XCTAssertTrue(later.sameData(as: first))
        XCTAssertFalse(snapshot(battery: 77).sameData(as: first))
    }

    /// The state under a sleeping car is from before it dozed off, so asleep
    /// has to win — a green "Charging" face hours after the charge ended
    /// would be a lie.
    func testAsleepOutranksTheChargingState() {
        XCTAssertEqual(snapshot(state: "Charging").statusText, "Charging")
        XCTAssertTrue(snapshot(state: "Charging").isCharging)
        XCTAssertEqual(snapshot(state: "Charging", asleep: true).statusText, "Asleep")
        XCTAssertFalse(snapshot(state: "Charging", asleep: true).isCharging)
        XCTAssertEqual(snapshot().statusText, "Not plugged in")
    }

    func testPluggedInFollowsTheChargingState() {
        XCTAssertEqual(snapshot(state: "Stopped").isPluggedIn, true)
        XCTAssertEqual(snapshot(state: "Disconnected").isPluggedIn, false)
        XCTAssertNil(snapshot(state: "SomethingNew").isPluggedIn)
        XCTAssertTrue(snapshot(state: "Starting").isCharging)
    }

    func testRangeFollowsTheUnitTheAppWrote() {
        XCTAssertEqual(snapshot().rangeText, "412 km")
        XCTAssertEqual(snapshot(unit: .miles).rangeText, "256 mi")
    }
}
