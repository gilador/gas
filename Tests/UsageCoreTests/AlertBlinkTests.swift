import XCTest
@testable import UsageCore

final class AlertBlinkTests: XCTestCase {
    func testDuration() {
        XCTAssertEqual(AlertBlink.duration, 10)
    }

    func testIsOnAtStart() {
        XCTAssertTrue(AlertBlink.isOn(elapsed: 0))
    }

    func testIsOffDuringFirstOffPhase() {
        XCTAssertFalse(AlertBlink.isOn(elapsed: 0.6))
    }

    func testIsOnAtSecondOnPhase() {
        XCTAssertTrue(AlertBlink.isOn(elapsed: 1.0))
    }

    func testIsOffAtLastOffPhase() {
        XCTAssertFalse(AlertBlink.isOn(elapsed: 9.9))
    }

    func testIsOffAtDuration() {
        XCTAssertFalse(AlertBlink.isOn(elapsed: 10.0))
    }

    func testIsOffForNegativeElapsed() {
        XCTAssertFalse(AlertBlink.isOn(elapsed: -1))
    }

    func testExactlyTenOnPhasesWhenSampled() {
        var wasOn = false
        var onPhases = 0
        var t: TimeInterval = 0
        while t < AlertBlink.duration {
            let isOn = AlertBlink.isOn(elapsed: t)
            if isOn && !wasOn { onPhases += 1 }
            wasOn = isOn
            t += 0.05
        }
        XCTAssertEqual(onPhases, AlertBlink.blinks)
    }
}
