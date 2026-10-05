import XCTest
@testable import Teslaris

/// Every call pins `parked` where the result depends on it, so a pace left
/// in the test runner's defaults can't change the outcome.
final class RefreshPolicyTests: XCTestCase {

    private func vehicle(state: String, minutesToFull: Int? = nil,
                         asleep: Bool = false) -> VehicleData {
        VehicleData(batteryPercentage: 60, rangeKm: 300, chargingState: state,
                    minutesToFull: minutesToFull, chargeLimitPercent: 90,
                    chargingPowerKw: 11, vehicleName: nil, vin: nil,
                    odometerKm: nil, isAsleep: asleep, lastUpdated: Date())
    }

    /// A moment `days` before the month's credits reset.
    private func beforeReset(days: Double) -> Date {
        let month = Calendar.current.dateInterval(of: .month, for: Date())!
        return month.end.addingTimeInterval(-days * 86_400)
    }

    func testParkedAndUnknownPollSlowly() {
        XCTAssertEqual(AppDelegate.refreshInterval(for: nil, monthlyRequests: 0,
                                                   parked: .fifteenMinutes), 900)
        XCTAssertEqual(AppDelegate.refreshInterval(
            for: vehicle(state: "Disconnected"), monthlyRequests: 0,
            parked: .fifteenMinutes), 900)
    }

    func testChargingScalesWithTimeToFull() {
        XCTAssertEqual(AppDelegate.refreshInterval(
            for: vehicle(state: "Charging", minutesToFull: 8 * 60), monthlyRequests: 0,
            parked: .fifteenMinutes), 300)
        XCTAssertEqual(AppDelegate.refreshInterval(
            for: vehicle(state: "Charging", minutesToFull: 45), monthlyRequests: 0,
            parked: .fifteenMinutes), 120)
        XCTAssertEqual(AppDelegate.refreshInterval(
            for: vehicle(state: "Charging", minutesToFull: 10), monthlyRequests: 0,
            parked: .fifteenMinutes), 60)
    }

    /// A stale "Charging" state on a sleeping car must never keep the
    /// fast poll running — asleep wins.
    func testAsleepBeatsCharging() {
        XCTAssertEqual(AppDelegate.refreshInterval(
            for: vehicle(state: "Charging", minutesToFull: 10, asleep: true),
            monthlyRequests: 0), 1800)
    }

    func testBudgetBrake() {
        // Late in the month the remaining credits easily last, so the brake
        // is its 30-minute floor.
        let late = beforeReset(days: 2)
        XCTAssertEqual(AppDelegate.refreshInterval(
            for: vehicle(state: "Disconnected"),
            monthlyRequests: UsageMeter.brakeThreshold, now: late), 1800)
        XCTAssertEqual(AppDelegate.refreshInterval(
            for: vehicle(state: "Charging", minutesToFull: 5),
            monthlyRequests: UsageMeter.brakeThreshold, now: late), 1800)
        XCTAssertEqual(AppDelegate.refreshInterval(
            for: vehicle(state: "Disconnected"),
            monthlyRequests: UsageMeter.brakeThreshold - 1, parked: .fifteenMinutes), 900)
    }

    /// Hitting the brake early must not run past the allowance: whatever
    /// the state or the chosen pace, the credits left last until the reset.
    func testBrakeNeverOutrunsTheAllowance() {
        let early = beforeReset(days: 25)
        let untilReset = UsageMeter.secondsLeftInMonth(from: early)
        for used in [UsageMeter.brakeThreshold, 4_900, UsageMeter.monthlyAllowance - 1] {
            let remaining = Double(UsageMeter.monthlyAllowance - used)
            for data in [vehicle(state: "Disconnected"),
                         vehicle(state: "Charging", minutesToFull: 5)] {
                let interval = AppDelegate.refreshInterval(
                    for: data, monthlyRequests: used, parked: .oneMinute, now: early)
                XCTAssertLessThanOrEqual(untilReset / interval, remaining + 0.001)
            }
        }
    }

    /// With nothing left, the next automatic poll is after the reset.
    func testSpentAllowanceWaitsForTheReset() {
        let now = beforeReset(days: 3)
        XCTAssertEqual(AppDelegate.refreshInterval(
            for: vehicle(state: "Charging", minutesToFull: 5),
            monthlyRequests: UsageMeter.monthlyAllowance, parked: .oneMinute, now: now),
            3 * 86_400, accuracy: 1)
    }

    /// The parked pace is the user's; the default must not poll more than
    /// Teslaris did before it was a choice.
    func testParkedFollowsTheChosenPace() {
        XCTAssertEqual(RefreshInterval.default, .fifteenMinutes)
        XCTAssertEqual(AppDelegate.refreshInterval(
            for: vehicle(state: "Disconnected"), monthlyRequests: 0, parked: .twoMinutes), 120)
        XCTAssertEqual(AppDelegate.refreshInterval(
            for: nil, monthlyRequests: 0, parked: .oneMinute), 60)
    }

    /// However eager the chosen pace, a sleeping car is still left alone.
    func testChosenPaceNeverSpeedsUpASleepingCar() {
        XCTAssertEqual(AppDelegate.refreshInterval(
            for: vehicle(state: "Disconnected", asleep: true),
            monthlyRequests: 0, parked: .oneMinute), 1800)
    }

    /// A long charge follows a faster parked pace rather than slowing down
    /// when plugged in, but is never slowed by a lazier one.
    func testChargingIsNeverSlowerThanParked() {
        XCTAssertEqual(AppDelegate.refreshInterval(
            for: vehicle(state: "Charging", minutesToFull: 8 * 60),
            monthlyRequests: 0, parked: .twoMinutes), 120)
        XCTAssertEqual(AppDelegate.refreshInterval(
            for: vehicle(state: "Charging", minutesToFull: 10),
            monthlyRequests: 0, parked: .fifteenMinutes), 60)
    }

    func testBrakeOverridesTheChosenPace() {
        XCTAssertEqual(AppDelegate.refreshInterval(
            for: vehicle(state: "Disconnected"),
            monthlyRequests: UsageMeter.brakeThreshold, parked: .oneMinute,
            now: beforeReset(days: 2)), 1800)
    }

    /// An overnight charge (8h) must stay around a dollar a month, not
    /// thirty: ~96 requests/night at the 5-minute cadence.
    func testOvernightChargeStaysInBudget() {
        let interval = AppDelegate.refreshInterval(
            for: vehicle(state: "Charging", minutesToFull: 8 * 60), monthlyRequests: 0,
            parked: .fifteenMinutes)
        let requestsPerNight = 8.0 * 3600 / interval
        XCTAssertLessThan(requestsPerNight * 30 * 0.002, 6.0)
    }
}
