import XCTest
import Foundation
@testable import UsageCore

final class XAIUsageMapperTests: XCTestCase {

    private func config(_ percent: Double? = 42.5, type: String? = "USAGE_PERIOD_TYPE_WEEKLY",
                        end: String? = "2026-01-12T09:00:00.000000+00:00",
                        billingEnd: String? = "2026-02-01T00:00:00.000000+00:00") -> XAIBillingResponse.Config {
        XAIBillingResponse.Config(creditUsagePercent: percent,
                                  currentPeriod: XAIBillingResponse.Period(type: type, end: end),
                                  billingPeriodEnd: billingEnd)
    }

    private func map(_ config: XAIBillingResponse.Config?) -> [UsageLimit] {
        XAIUsageMapper.map(config, warning: 80, critical: 95)
    }

    private func date(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    func testWeeklyPeriodIsTheWeeklyLimit() {
        let limits = map(config())
        XCTAssertEqual(limits.map(\.id), ["weekly_all"])
        XCTAssertEqual(limits.map(\.label), ["Weekly"])
        XCTAssertEqual(limits.first?.percentUsed, 42.5)
        XCTAssertEqual(limits.first?.resetsAt, date("2026-01-12T09:00:00Z"))
        XCTAssertEqual(limits.first?.severity, .normal)
    }

    func testMonthlyPeriod() {
        let limits = map(config(type: "USAGE_PERIOD_TYPE_MONTHLY"))
        XCTAssertEqual(limits.map(\.id), ["monthly"])
        XCTAssertEqual(limits.map(\.label), ["Monthly"])
    }

    func testUnknownPeriodIsUsage() {
        for type in ["USAGE_PERIOD_TYPE_DAILY", "", nil] as [String?] {
            let limits = map(config(type: type))
            XCTAssertEqual(limits.map(\.id), ["monthly"], type ?? "nil")
            XCTAssertEqual(limits.map(\.label), ["Usage"], type ?? "nil")
        }
    }

    func testResetFallsBackToTheBillingPeriodEnd() {
        XCTAssertEqual(map(config(end: nil)).first?.resetsAt, date("2026-02-01T00:00:00Z"))
        XCTAssertEqual(map(config(end: "garbage")).first?.resetsAt, date("2026-02-01T00:00:00Z"))
    }

    func testNoResetWhenNeitherDateIsKnown() {
        let limits = map(config(end: nil, billingEnd: nil))
        XCTAssertEqual(limits.count, 1)
        XCTAssertNil(limits.first?.resetsAt)
    }

    func testMissingPercentGivesNoLimits() {
        XCTAssertTrue(map(config(nil)).isEmpty)
        XCTAssertTrue(map(nil).isEmpty)
    }

    func testSeverityAtTheThresholds() {
        XCTAssertEqual(map(config(79.9)).first?.severity, .normal)
        XCTAssertEqual(map(config(80)).first?.severity, .warning)
        XCTAssertEqual(map(config(95)).first?.severity, .critical)
        XCTAssertEqual(map(config(100)).first?.severity, .critical)
    }

    func testFractionalSecondsAndOffsets() {
        XCTAssertEqual(map(config(end: "2026-01-12T11:00:00.123456+02:00")).first?.resetsAt?.timeIntervalSince1970 ?? 0,
                       date("2026-01-12T09:00:00Z").timeIntervalSince1970 + 0.123, accuracy: 0.001)
        XCTAssertEqual(map(config(end: "2026-01-12T09:00:00Z")).first?.resetsAt, date("2026-01-12T09:00:00Z"))
    }

    func testFixtureMapsToOneWeeklyLimit() throws {
        let decoded = try JSONDecoder().decode(XAIBillingResponse.self, from: try Fixtures.data("xai_billing_response"))
        let limits = map(decoded.config)
        XCTAssertEqual(limits.map(\.id), ["weekly_all"])
        XCTAssertEqual(limits.first?.percentUsed, 42.5)
    }
}
