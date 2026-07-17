import XCTest
import Foundation
@testable import UsageCore

final class ThresholdEvaluatorTests: XCTestCase {
    private func limit(_ pct: Double, resetsAt: Double? = 1000) -> UsageLimit {
        UsageLimit(id: "five_hour", label: "Session (5h)", percentUsed: pct,
                   resetsAt: resetsAt.map { Date(timeIntervalSince1970: $0) }, severity: .normal)
    }
    private func snap(_ limits: [UsageLimit]) -> UsageSnapshot {
        UsageSnapshot(provider: .claude, fetchedAt: Date(), limits: limits, status: .ok)
    }

    func testFiresOnCrossing() {
        var state = NotificationState()
        let crossings = ThresholdEvaluator.evaluate(snap([limit(82)]), state: &state,
                                                    thresholds: [80, 95])
        XCTAssertEqual(crossings.count, 1)
        XCTAssertEqual(crossings.first?.threshold, 80)
    }

    func testBothThresholdsFireWhenAboveBoth() {
        var state = NotificationState()
        let crossings = ThresholdEvaluator.evaluate(snap([limit(96)]), state: &state,
                                                    thresholds: [80, 95])
        XCTAssertEqual(Set(crossings.map { $0.threshold }), [80, 95])
    }

    func testDoesNotRefireSameWindow() {
        var state = NotificationState()
        _ = ThresholdEvaluator.evaluate(snap([limit(82)]), state: &state, thresholds: [80])
        let second = ThresholdEvaluator.evaluate(snap([limit(85)]), state: &state, thresholds: [80])
        XCTAssertTrue(second.isEmpty)
    }

    func testRefiresAfterWindowResets() {
        var state = NotificationState()
        _ = ThresholdEvaluator.evaluate(snap([limit(82, resetsAt: 1000)]), state: &state, thresholds: [80])
        let after = ThresholdEvaluator.evaluate(snap([limit(82, resetsAt: 2000)]), state: &state, thresholds: [80])
        XCTAssertEqual(after.count, 1)
    }

    func testRefiresAfterDroppingBelowThenClimbing() {
        var state = NotificationState()
        _ = ThresholdEvaluator.evaluate(snap([limit(82)]), state: &state, thresholds: [80])
        _ = ThresholdEvaluator.evaluate(snap([limit(70)]), state: &state, thresholds: [80])
        let refire = ThresholdEvaluator.evaluate(snap([limit(83)]), state: &state, thresholds: [80])
        XCTAssertEqual(refire.count, 1)
    }

    func testStateIsCodableRoundTrip() throws {
        var state = NotificationState()
        _ = ThresholdEvaluator.evaluate(snap([limit(82)]), state: &state, thresholds: [80])
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(NotificationState.self, from: data)
        XCTAssertEqual(decoded, state)
    }
}
