import XCTest
@testable import Teslaris

/// Like the low-battery reminder, the warning is only worth having if it
/// says so once: a slow puncture lasts days, and so would the nagging.
final class TyrePressureTests: XCTestCase {

    func testFiresWhenTheCarFlagsAWheel() {
        let outcome = TyreWatch.evaluate(lowTyres: [.rearLeft], warned: false)
        XCTAssertTrue(outcome.notify)
        XCTAssertTrue(outcome.warned)
    }

    func testFiresOnlyOncePerEpisode() {
        let outcome = TyreWatch.evaluate(lowTyres: [.rearLeft], warned: true)
        XCTAssertFalse(outcome.notify)
        XCTAssertTrue(outcome.warned)
    }

    func testRearmsOnceEveryWheelIsFine() {
        let outcome = TyreWatch.evaluate(lowTyres: [], warned: true)
        XCTAssertFalse(outcome.notify)
        XCTAssertFalse(outcome.warned)
    }

    /// A car with no readings yet must neither warn nor re-arm, or every
    /// wake from sleep would repeat a warning the owner has already seen.
    func testUnknownLeavesEverythingAsItWas() {
        XCTAssertEqual(TyreWatch.evaluate(lowTyres: nil, warned: true),
                       TyreWatch.Outcome(notify: false, warned: true))
        XCTAssertEqual(TyreWatch.evaluate(lowTyres: nil, warned: false),
                       TyreWatch.Outcome(notify: false, warned: false))
    }

    func testSummaryNamesEachWheelWithItsPressure() {
        let summary = TyreWatch.summary(lowTyres: [.frontLeft, .rearRight],
                                        pressuresBar: [.frontLeft: 2.14, .rearRight: 2.3],
                                        unit: "Bar")
        XCTAssertEqual(summary, "Front left 2.1 bar · Rear right 2.3 bar")
    }

    func testSummaryFollowsTheCarsUnit() {
        let summary = TyreWatch.summary(lowTyres: [.rearLeft],
                                        pressuresBar: [.rearLeft: 2.0],
                                        unit: "Psi")
        XCTAssertEqual(summary, "Rear left 29 psi")
    }

    func testReadingIsNilWithoutAPressure() {
        XCTAssertNil(TyreWatch.reading(bar: nil, unit: "Bar"))
        XCTAssertEqual(TyreWatch.reading(bar: 2.9, unit: nil), "2.9 bar")
    }

    func testSummaryWithoutAReadingStillNamesTheWheel() {
        let summary = TyreWatch.summary(lowTyres: [.rearLeft], pressuresBar: [:], unit: nil)
        XCTAssertEqual(summary, "Rear left")
    }
}
