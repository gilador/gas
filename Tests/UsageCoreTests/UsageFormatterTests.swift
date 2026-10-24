import XCTest
@testable import UsageCore

final class UsageFormatterTests: XCTestCase {
    private func snap(_ provider: ProviderID, _ pcts: [Double], status: FetchStatus = .ok) -> UsageSnapshot {
        let limits = pcts.enumerated().map { i, p in
            UsageLimit(id: "l\(i)", label: "l\(i)", percentUsed: p, resetsAt: nil, severity: .normal)
        }
        return UsageSnapshot(provider: provider, fetchedAt: Date(), limits: limits, status: status)
    }

    func testThreeProvidersCompactNoSpaces() {
        let board = UsageBoard(snapshots: [snap(.claude, [42]), snap(.openai, [52]), snap(.xai, [7])])
        XCTAssertEqual(UsageFormatter.compactLabel(for: board), "◐42%|⬡52%|✕7%")
    }

    func testTwoProvidersCompactNoSpaces() {
        let board = UsageBoard(snapshots: [snap(.claude, [12, 42]), snap(.openai, [52, 7])])
        XCTAssertEqual(UsageFormatter.compactLabel(for: board), "◐42%|⬡52%|✕—")
    }

    func testOnlyClaudeShowsDashForOpenAI() {
        let board = UsageBoard(snapshots: [snap(.claude, [42])])
        XCTAssertEqual(UsageFormatter.compactLabel(for: board), "◐42%|⬡—|✕—")
    }

    func testOnlyOpenAIShowsDashForClaude() {
        let board = UsageBoard(snapshots: [snap(.openai, [100])])
        XCTAssertEqual(UsageFormatter.compactLabel(for: board), "◐—|⬡100%|✕—")
    }

    func testProviderWithoutLimitsShowsDash() {
        let board = UsageBoard(snapshots: [snap(.claude, [], status: .stale(reason: "x")), snap(.openai, [52])])
        XCTAssertEqual(UsageFormatter.compactLabel(for: board), "◐—|⬡52%|✕—")
    }

    func testEmptyBoardShowsDashForEveryProvider() {
        XCTAssertEqual(UsageFormatter.compactLabel(for: UsageBoard()), "◐—|⬡—|✕—")
    }

    func testPercentIsRoundedUp() {
        let board = UsageBoard(snapshots: [snap(.claude, [41.2])])
        XCTAssertEqual(UsageFormatter.compactLabel(for: board), "◐42%|⬡—|✕—")
    }
}
