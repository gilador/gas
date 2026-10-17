import XCTest
import Foundation
@testable import UsageCore

final class OpenAIUsageMapperTests: XCTestCase {
    private func window(_ pct: Double, seconds: Int? = 18000, resetAt: Double? = 1_789_726_348)
        -> OpenAIUsageResponse.Window {
        OpenAIUsageResponse.Window(usedPercent: pct, limitWindowSeconds: seconds, resetAt: resetAt)
    }
    private func rateLimit(primary: OpenAIUsageResponse.Window?, secondary: OpenAIUsageResponse.Window?)
        -> OpenAIUsageResponse.RateLimit {
        OpenAIUsageResponse.RateLimit(primaryWindow: primary, secondaryWindow: secondary)
    }

    func testPrimaryAndSecondaryMapToSessionAndWeekly() {
        let limits = OpenAIUsageMapper.map(
            rateLimit(primary: window(32), secondary: window(56, seconds: 604_800, resetAt: 1_789_883_756)),
            warning: 80, critical: 95)
        XCTAssertEqual(limits.map(\.id), ["session", "weekly_all"])
        XCTAssertEqual(limits.map(\.label), ["Session (5h)", "Weekly"])
        XCTAssertEqual(limits.map(\.percentUsed), [32, 56])
        XCTAssertEqual(limits[0].resetsAt, Date(timeIntervalSince1970: 1_789_726_348))
        XCTAssertEqual(limits[1].resetsAt, Date(timeIntervalSince1970: 1_789_883_756))
    }

    func testLabelRules() {
        XCTAssertEqual(OpenAIUsageMapper.label(windowSeconds: 18000, fallback: "Session"), "Session (5h)")
        XCTAssertEqual(OpenAIUsageMapper.label(windowSeconds: 3600, fallback: "Session"), "Session (1h)")
        XCTAssertEqual(OpenAIUsageMapper.label(windowSeconds: 604_800, fallback: "Weekly"), "Weekly")
        XCTAssertEqual(OpenAIUsageMapper.label(windowSeconds: 259_200, fallback: "Weekly"), "3-day")
        XCTAssertEqual(OpenAIUsageMapper.label(windowSeconds: nil, fallback: "Weekly"), "Weekly")
    }

    func testNilResetAtMapsToNil() {
        let limits = OpenAIUsageMapper.map(rateLimit(primary: window(1, resetAt: nil), secondary: nil),
                                           warning: 80, critical: 95)
        XCTAssertNil(limits[0].resetsAt)
    }

    func testMissingWindowIsOmitted() {
        let limits = OpenAIUsageMapper.map(rateLimit(primary: nil, secondary: window(56, seconds: 604_800)),
                                           warning: 80, critical: 95)
        XCTAssertEqual(limits.map(\.id), ["weekly_all"])
    }

    func testNilRateLimitMapsToEmpty() {
        XCTAssertEqual(OpenAIUsageMapper.map(nil, warning: 80, critical: 95), [])
    }

    func testSeverityFromThresholds() {
        let limits = OpenAIUsageMapper.map(rateLimit(primary: window(82), secondary: window(96)),
                                           warning: 80, critical: 95)
        XCTAssertEqual(limits.map(\.severity), [.warning, .critical])
    }

    func testWeeklyOnlyPrimaryWindowMapsToWeekly() {
        let limits = OpenAIUsageMapper.map(rateLimit(primary: window(40, seconds: 604_800), secondary: nil),
                                           warning: 80, critical: 95)
        XCTAssertEqual(limits.map(\.id), ["weekly_all"])
        XCTAssertEqual(limits.map(\.label), ["Weekly"])
    }

    func testShortSecondaryWindowMapsToSession() {
        let limits = OpenAIUsageMapper.map(rateLimit(primary: window(40, seconds: 604_800), secondary: window(10)),
                                           warning: 80, critical: 95)
        XCTAssertEqual(limits.map(\.id), ["weekly_all", "session"])
    }

    func testClashingWindowsKeepPositionalIds() {
        let limits = OpenAIUsageMapper.map(
            rateLimit(primary: window(40, seconds: 604_800), secondary: window(50, seconds: 604_800)),
            warning: 80, critical: 95)
        XCTAssertEqual(limits.map(\.id), ["session", "weekly_all"])
    }

    func testUnknownLengthKeepsPositionalId() {
        let limits = OpenAIUsageMapper.map(rateLimit(primary: window(40, seconds: nil), secondary: nil),
                                           warning: 80, critical: 95)
        XCTAssertEqual(limits.map(\.id), ["session"])
    }
}
