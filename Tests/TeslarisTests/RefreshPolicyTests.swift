import XCTest
@testable import Teslaris

final class RefreshPolicyTests: XCTestCase {

    private func vehicle(state: String, minutesToFull: Int? = nil,
                         asleep: Bool = false) -> VehicleData {
        VehicleData(batteryPercentage: 60, rangeKm: 300, chargingState: state,
                    minutesToFull: minutesToFull, chargeLimitPercent: 90,
                    chargingPowerKw: 11, vehicleName: nil, vin: nil,
                    odometerKm: nil, isAsleep: asleep, lastUpdated: Date())
    }

    func testParkedAndUnknownPollSlowly() {
        XCTAssertEqual(AppDelegate.refreshInterval(for: nil, monthlyRequests: 0), 900)
        XCTAssertEqual(AppDelegate.refreshInterval(
            for: vehicle(state: "Disconnected"), monthlyRequests: 0), 900)
    }

    func testChargingScalesWithTimeToFull() {
        XCTAssertEqual(AppDelegate.refreshInterval(
            for: vehicle(state: "Charging", minutesToFull: 8 * 60), monthlyRequests: 0), 300)
        XCTAssertEqual(AppDelegate.refreshInterval(
            for: vehicle(state: "Charging", minutesToFull: 45), monthlyRequests: 0), 120)
        XCTAssertEqual(AppDelegate.refreshInterval(
            for: vehicle(state: "Charging", minutesToFull: 10), monthlyRequests: 0), 60)
    }

    /// A stale "Charging" state on a sleeping car must never keep the
    /// fast poll running — asleep wins.
    func testAsleepBeatsCharging() {
        XCTAssertEqual(AppDelegate.refreshInterval(
            for: vehicle(state: "Charging", minutesToFull: 10, asleep: true),
            monthlyRequests: 0), 1800)
    }

    func testBudgetBrake() {
        XCTAssertEqual(AppDelegate.refreshInterval(
            for: vehicle(state: "Disconnected"), monthlyRequests: 4201), 1800)
        XCTAssertEqual(AppDelegate.refreshInterval(
            for: vehicle(state: "Charging", minutesToFull: 5), monthlyRequests: 4201), 1800)
    }

    /// An overnight charge (8h) must stay around a dollar a month, not
    /// thirty: ~96 requests/night at the 5-minute cadence.
    func testOvernightChargeStaysInBudget() {
        let interval = AppDelegate.refreshInterval(
            for: vehicle(state: "Charging", minutesToFull: 8 * 60), monthlyRequests: 0)
        let requestsPerNight = 8.0 * 3600 / interval
        XCTAssertLessThan(requestsPerNight * 30 * 0.002, 6.0)
    }
}
