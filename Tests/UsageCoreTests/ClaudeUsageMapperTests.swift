import XCTest
import Foundation
@testable import UsageCore

final class ClaudeUsageMapperTests: XCTestCase {
    private func entry(_ kind: String, _ pct: Double,
                       resetsAt: String? = "2026-01-01T18:00:00.000000+00:00",
                       model: String? = nil) -> ClaudeUsageResponse.Entry {
        ClaudeUsageResponse.Entry(
            kind: kind, group: nil, percent: pct, severity: nil, resetsAt: resetsAt,
            scope: model.map {
                ClaudeUsageResponse.Scope(
                    model: ClaudeUsageResponse.Model(id: nil, displayName: $0))
            },
            isActive: nil)
    }

    func testSessionMapsToSession() {
        let limits = ClaudeUsageMapper.map([entry("session", 40)], warning: 80, critical: 95)
        XCTAssertEqual(limits.count, 1)
        XCTAssertEqual(limits[0].id, "session")
        XCTAssertEqual(limits[0].label, "Session (5h)")
        XCTAssertEqual(limits[0].percentUsed, 40)
        XCTAssertEqual(limits[0].severity, .normal)
    }

    func testWeeklyAllMapsToWeekly() {
        let limits = ClaudeUsageMapper.map([entry("weekly_all", 40)], warning: 80, critical: 95)
        XCTAssertEqual(limits[0].label, "Weekly")
        XCTAssertEqual(limits[0].id, "weekly_all")
    }

    func testWeeklyScopedUsesDisplayName() {
        let limits = ClaudeUsageMapper.map([entry("weekly_scoped", 60, model: "Claude Opus 4")],
                                           warning: 80, critical: 95)
        XCTAssertEqual(limits[0].label, "Weekly (Claude Opus 4)")
        XCTAssertEqual(limits[0].id, "weekly_scoped#Claude Opus 4")
    }

    func testWeeklyScopedWithoutDisplayName() {
        let limits = ClaudeUsageMapper.map([entry("weekly_scoped", 20)], warning: 80, critical: 95)
        XCTAssertEqual(limits[0].label, "Weekly (scoped)")
        XCTAssertEqual(limits[0].id, "weekly_scoped")
    }

    func testUnknownKindGetsGenericLabel() {
        let limits = ClaudeUsageMapper.map([entry("monthly_special", 10)], warning: 80, critical: 95)
        XCTAssertEqual(limits[0].label, "Monthly Special")
        XCTAssertEqual(limits[0].id, "monthly_special")
    }

    func testSeverityCrossesToCritical() {
        let limits = ClaudeUsageMapper.map([entry("weekly_all", 96)], warning: 80, critical: 95)
        XCTAssertEqual(limits[0].severity, .critical)
    }

    func testResetsAtParsesISOString() {
        let limits = ClaudeUsageMapper.map(
            [entry("session", 40, resetsAt: "2026-01-01T18:00:00.000000+00:00")],
            warning: 80, critical: 95)
        // Derive the expected Date from the same ISO components (no hardcoded interval).
        var comps = DateComponents()
        comps.year = 2026; comps.month = 1; comps.day = 1
        comps.hour = 18; comps.minute = 0; comps.second = 0
        comps.timeZone = TimeZone(identifier: "UTC")
        let expected = Calendar(identifier: .gregorian).date(from: comps)!
        XCTAssertEqual(limits[0].resetsAt, expected)
    }

    func testNilResetsAtMapsToNil() {
        let limits = ClaudeUsageMapper.map([entry("session", 10, resetsAt: nil)],
                                           warning: 80, critical: 95)
        XCTAssertNil(limits[0].resetsAt)
    }
}
