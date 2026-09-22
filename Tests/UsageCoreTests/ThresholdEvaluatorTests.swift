import XCTest
import Foundation
@testable import UsageCore

final class ThresholdEvaluatorTests: XCTestCase {
    private func limit(_ pct: Double, resetsAt: Double? = 1000) -> UsageLimit {
        UsageLimit(id: "five_hour", label: "Session (5h)", percentUsed: pct,
                   resetsAt: resetsAt.map { Date(timeIntervalSince1970: $0) }, severity: .normal)
    }
    private func snap(_ limits: [UsageLimit], provider: ProviderID = .claude) -> UsageSnapshot {
        UsageSnapshot(provider: provider, fetchedAt: Date(), limits: limits, status: .ok)
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

    func testSameLimitIDOnTwoProvidersFiresTwice() {
        var state = NotificationState()
        let claude = ThresholdEvaluator.evaluate(snap([limit(82)], provider: .claude),
                                                 state: &state, thresholds: [80])
        let openai = ThresholdEvaluator.evaluate(snap([limit(82)], provider: .openai),
                                                 state: &state, thresholds: [80])
        XCTAssertEqual(claude.count, 1)
        XCTAssertEqual(openai.count, 1)
        XCTAssertEqual(claude.first?.provider, .claude)
        XCTAssertEqual(openai.first?.provider, .openai)
    }

    func testStateKeyIncludesProvider() {
        var state = NotificationState()
        _ = ThresholdEvaluator.evaluate(snap([limit(82)], provider: .openai), state: &state, thresholds: [80])
        XCTAssertEqual(Array(state.fired.keys), ["openai#five_hour#80.0"])
    }

    func testOneProviderDroppingDoesNotClearTheOther() {
        var state = NotificationState()
        _ = ThresholdEvaluator.evaluate(snap([limit(82)], provider: .claude), state: &state, thresholds: [80])
        _ = ThresholdEvaluator.evaluate(snap([limit(82)], provider: .openai), state: &state, thresholds: [80])
        _ = ThresholdEvaluator.evaluate(snap([limit(10)], provider: .openai), state: &state, thresholds: [80])
        let claudeAgain = ThresholdEvaluator.evaluate(snap([limit(85)], provider: .claude),
                                                      state: &state, thresholds: [80])
        XCTAssertTrue(claudeAgain.isEmpty)
    }

    func testResetTimeJitterDoesNotRefire() {
        var state = NotificationState()
        _ = ThresholdEvaluator.evaluate(snap([limit(82, resetsAt: 1_790_168_400)]), state: &state, thresholds: [80])
        let later = ThresholdEvaluator.evaluate(snap([limit(85, resetsAt: 1_790_168_398.805)]), state: &state, thresholds: [80])
        let again = ThresholdEvaluator.evaluate(snap([limit(86, resetsAt: 1_790_168_400.805)]), state: &state, thresholds: [80])
        XCTAssertTrue(later.isEmpty)
        XCTAssertTrue(again.isEmpty)
    }
}
