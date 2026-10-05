import XCTest
@testable import Teslaris

/// The failures worth guarding against: warning someone who is standing at
/// the open boot, warning twice, and never warning at all.
final class UnlockedTests: XCTestCase {

    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func evaluate(locked: Bool? = false,
                          userPresent: Bool = false,
                          state: UnlockedWatch.State? = nil,
                          after seconds: TimeInterval = 0) -> UnlockedWatch.Outcome {
        UnlockedWatch.evaluate(locked: locked, userPresent: userPresent,
                               state: state, now: start.addingTimeInterval(seconds))
    }

    func testFirstUnlockedReadingOnlyStartsTheClock() {
        let outcome = evaluate()
        XCTAssertFalse(outcome.notify)
        XCTAssertEqual(outcome.state,
                       UnlockedWatch.State(since: start, lastSeen: start, warned: false))
    }

    func testFiresOnceTheDelayHasPassed() {
        let first = evaluate()
        let second = evaluate(state: first.state, after: 15 * 60)
        XCTAssertTrue(second.notify)
        XCTAssertEqual(second.state?.since, start)
        XCTAssertEqual(second.state?.warned, true)
    }

    func testStaysQuietBeforeTheDelay() {
        let first = evaluate()
        XCTAssertFalse(evaluate(state: first.state, after: 5 * 60).notify)
    }

    func testFiresOnlyOncePerStretch() {
        let first = evaluate()
        let second = evaluate(state: first.state, after: 15 * 60)
        let third = evaluate(state: second.state, after: 30 * 60)
        XCTAssertFalse(third.notify)
        XCTAssertEqual(third.state?.warned, true)
    }

    func testLockingEndsTheStretch() {
        let first = evaluate()
        let locked = evaluate(locked: true, state: first.state, after: 5 * 60)
        XCTAssertEqual(locked, UnlockedWatch.Outcome(notify: false, state: nil))
        // Unlocked again later: a new stretch, with its own delay.
        XCTAssertFalse(evaluate(state: locked.state, after: 20 * 60).notify)
    }

    func testSomeoneInTheCarIsNotAForgottenCar() {
        let first = evaluate()
        let occupied = evaluate(userPresent: true, state: first.state, after: 15 * 60)
        XCTAssertEqual(occupied, UnlockedWatch.Outcome(notify: false, state: nil))
    }

    func testUnknownLockStateKeepsTheClock() {
        let first = evaluate()
        let unknown = evaluate(locked: nil, state: first.state, after: 15 * 60)
        XCTAssertFalse(unknown.notify)
        XCTAssertEqual(unknown.state, first.state)
    }

    /// The Mac slept overnight; the car was locked and unlocked meanwhile.
    /// The reading after the gap must not count the gap as unlocked time.
    func testALongGapRestartsTheClock() {
        let first = evaluate()
        let later = UnlockedWatch.staleAfter + 60
        let afterGap = evaluate(state: first.state, after: later)
        XCTAssertFalse(afterGap.notify)
        XCTAssertEqual(afterGap.state?.since, start.addingTimeInterval(later))
    }

    /// A sleeping car is polled every 30 minutes — well inside the gap that
    /// restarts the clock, or a car asleep and unlocked would never warn.
    func testAsleepCadenceStillFires() {
        XCTAssertLessThan(1800, UnlockedWatch.staleAfter)
        let first = evaluate()
        XCTAssertTrue(evaluate(state: first.state, after: 1800).notify)
    }
}
