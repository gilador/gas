import XCTest
import Foundation
@testable import UsageCore

final class ThresholdEvaluatorTests: XCTestCase {
    private func limit(_ pct: Double, id: String = "five_hour", resetsAt: Double? = 1000) -> UsageLimit {
        UsageLimit(id: id, label: id, percentUsed: pct,
                   resetsAt: resetsAt.map { Date(timeIntervalSince1970: $0) }, severity: .normal)
    }
    private func snap(_ limits: [UsageLimit], provider: ProviderID = .claude) -> UsageSnapshot {
        UsageSnapshot(provider: provider, fetchedAt: Date(), limits: limits, status: .ok)
    }
    private func eval(_ snapshot: UsageSnapshot, _ state: inout NotificationState,
                      warning: Double = 80, critical: Double = 95) -> [ThresholdCrossing] {
        ThresholdEvaluator.evaluate(snapshot, state: &state, warning: warning, critical: critical)
    }

    func testWarningFiresOnce() {
        var state = NotificationState()
        let first = eval(snap([limit(82)]), &state)
        XCTAssertEqual(first.map(\.level), [.warning])
        XCTAssertEqual(first.first?.threshold, 80)
    }

    func testCriticalFiresAfterWarningInSameWindow() {
        var state = NotificationState()
        _ = eval(snap([limit(82)]), &state)
        let later = eval(snap([limit(96)]), &state)
        XCTAssertEqual(later.map(\.level), [.critical])
    }

    func testJumpPastBothFiresBothLevels() {
        var state = NotificationState()
        XCTAssertEqual(eval(snap([limit(96)]), &state).map(\.level), [.warning, .critical])
    }

    func testDoesNotRefireSameWindow() {
        var state = NotificationState()
        _ = eval(snap([limit(96)]), &state)
        XCTAssertTrue(eval(snap([limit(99)]), &state).isEmpty)
    }

    func testRefiresAfterWindowResets() {
        var state = NotificationState()
        _ = eval(snap([limit(82, resetsAt: 1000)]), &state)
        XCTAssertEqual(eval(snap([limit(82, resetsAt: 20_000)]), &state).map(\.level), [.warning])
    }

    func testDroppingBelowDoesNotRearmWithinWindow() {
        var state = NotificationState()
        _ = eval(snap([limit(82)]), &state)
        _ = eval(snap([limit(70)]), &state)
        XCTAssertTrue(eval(snap([limit(83)]), &state).isEmpty)
    }

    func testChangingThresholdRearmsThatLevel() {
        var state = NotificationState()
        _ = eval(snap([limit(82)]), &state, warning: 80)
        XCTAssertEqual(eval(snap([limit(82)]), &state, warning: 75).map(\.level), [.warning])
        XCTAssertTrue(eval(snap([limit(82)]), &state, warning: 75).isEmpty)
    }

    func testChangingWarningDoesNotRearmCritical() {
        var state = NotificationState()
        _ = eval(snap([limit(96)]), &state, warning: 80, critical: 95)
        XCTAssertEqual(eval(snap([limit(96)]), &state, warning: 70, critical: 95).map(\.level), [.warning])
    }

    func testRaisedThresholdAlertsWhenUsageReachesIt() {
        var state = NotificationState()
        _ = eval(snap([limit(82)]), &state, warning: 80)
        XCTAssertTrue(eval(snap([limit(84)]), &state, warning: 90).isEmpty)
        XCTAssertEqual(eval(snap([limit(91)]), &state, warning: 90).map(\.level), [.warning])
    }

    func testFlagWithoutRecordedThresholdStaysQuiet() throws {
        let legacy = #"{"fired":{"claude#five_hour#warning":1000}}"#.data(using: .utf8)!
        var state = try JSONDecoder().decode(NotificationState.self, from: legacy)
        XCTAssertTrue(eval(snap([limit(82)]), &state, warning: 75).isEmpty)
    }

    func testEachLimitHasItsOwnFlag() {
        var state = NotificationState()
        let crossings = eval(snap([limit(90, id: "session"), limit(90, id: "weekly_scoped#Fable")]), &state)
        XCTAssertEqual(crossings.map(\.limit.id), ["session", "weekly_scoped#Fable"])
    }

    func testSameLimitIDOnTwoProvidersFiresTwice() {
        var state = NotificationState()
        let claude = eval(snap([limit(82)], provider: .claude), &state)
        let openai = eval(snap([limit(82)], provider: .openai), &state)
        XCTAssertEqual(claude.first?.provider, .claude)
        XCTAssertEqual(openai.first?.provider, .openai)
    }

    func testStateKeyIsProviderLimitLevel() {
        var state = NotificationState()
        _ = eval(snap([limit(82)], provider: .openai), &state)
        XCTAssertEqual(Array(state.fired.keys), ["openai#five_hour#warning"])
    }

    func testResetTimeJitterDoesNotRefire() {
        var state = NotificationState()
        _ = eval(snap([limit(82, resetsAt: 1_790_168_400)]), &state)
        XCTAssertTrue(eval(snap([limit(85, resetsAt: 1_790_168_398.805)]), &state).isEmpty)
        XCTAssertTrue(eval(snap([limit(86, resetsAt: 1_790_168_400.805)]), &state).isEmpty)
    }

    func testStateIsCodableRoundTrip() throws {
        var state = NotificationState()
        _ = eval(snap([limit(96)]), &state)
        let decoded = try JSONDecoder().decode(NotificationState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(decoded, state)
    }
}
