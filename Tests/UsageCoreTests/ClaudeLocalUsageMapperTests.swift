import XCTest
import Foundation
@testable import UsageCore

final class ClaudeLocalUsageMapperTests: XCTestCase {
    private let warning = 80.0
    private let critical = 95.0

    func testMapsBothWindowsInOrder() {
        let usage = ClaudeLocalUsage(
            fiveHour: .init(usedPercentage: 40, resetsAt: Date(timeIntervalSince1970: 1700000000)),
            sevenDay: .init(usedPercentage: 60, resetsAt: Date(timeIntervalSince1970: 1700600000)),
            updatedAt: Date())
        let limits = ClaudeLocalUsageMapper.map(usage, warning: warning, critical: critical)
        XCTAssertEqual(limits.map(\.id), ["session", "weekly_all"])
        XCTAssertEqual(limits.map(\.label), ["Session (5h)", "Weekly"])
        XCTAssertEqual(limits[0].percentUsed, 40)
        XCTAssertEqual(limits[0].resetsAt, Date(timeIntervalSince1970: 1700000000))
        XCTAssertEqual(limits[1].percentUsed, 60)
        XCTAssertEqual(limits[1].resetsAt, Date(timeIntervalSince1970: 1700600000))
    }

    func testOnlyFiveHourProducesOneLimit() {
        let usage = ClaudeLocalUsage(fiveHour: .init(usedPercentage: 10, resetsAt: nil),
                                     sevenDay: nil, updatedAt: Date())
        let limits = ClaudeLocalUsageMapper.map(usage, warning: warning, critical: critical)
        XCTAssertEqual(limits.map(\.id), ["session"])
    }

    func testOnlySevenDayProducesOneLimit() {
        let usage = ClaudeLocalUsage(fiveHour: nil,
                                     sevenDay: .init(usedPercentage: 10, resetsAt: nil),
                                     updatedAt: Date())
        let limits = ClaudeLocalUsageMapper.map(usage, warning: warning, critical: critical)
        XCTAssertEqual(limits.map(\.id), ["weekly_all"])
    }

    func testSeverityThresholds() {
        let usage = ClaudeLocalUsage(fiveHour: .init(usedPercentage: 96, resetsAt: nil),
                                     sevenDay: .init(usedPercentage: 85, resetsAt: nil),
                                     updatedAt: Date())
        let limits = ClaudeLocalUsageMapper.map(usage, warning: warning, critical: critical)
        XCTAssertEqual(limits[0].severity, .critical)
        XCTAssertEqual(limits[1].severity, .warning)
    }
}
