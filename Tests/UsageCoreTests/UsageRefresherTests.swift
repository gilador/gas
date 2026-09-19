import XCTest
import Foundation
@testable import UsageCore

final class UsageRefresherTests: XCTestCase {
    private func limit(_ pct: Double) -> UsageLimit {
        UsageLimit(id: "session", label: "Session", percentUsed: pct, resetsAt: nil, severity: .normal)
    }
    private func snap(_ provider: ProviderID, limits: [UsageLimit] = [],
                      fetchedAt: TimeInterval = 0, status: FetchStatus = .ok) -> UsageSnapshot {
        UsageSnapshot(provider: provider, fetchedAt: Date(timeIntervalSince1970: fetchedAt),
                      limits: limits, status: status)
    }

    func testBothOkLandInBoard() async {
        let providers: [any UsageProvider] = [
            StubUsageProvider(id: .claude, result: .success(snap(.claude, limits: [limit(40)]))),
            StubUsageProvider(id: .openai, result: .success(snap(.openai, limits: [limit(50)])))
        ]
        let board = await UsageRefresher.refresh(UsageBoard(), providers: providers)
        XCTAssertEqual(board.snapshots.map(\.provider), [.claude, .openai])
        XCTAssertEqual(board.snapshot(for: .openai)?.limits.first?.percentUsed, 50)
    }

    func testThrowingProviderBecomesErrorWithoutBlockingTheOther() async {
        let providers: [any UsageProvider] = [
            StubUsageProvider(id: .claude, result: .failure(StubError())),
            StubUsageProvider(id: .openai, result: .success(snap(.openai, limits: [limit(50)])))
        ]
        let board = await UsageRefresher.refresh(UsageBoard(), providers: providers)
        XCTAssertEqual(board.snapshot(for: .claude)?.status, .error(message: "Fetch failed"))
        XCTAssertEqual(board.snapshot(for: .claude)?.limits.isEmpty, true)
        XCTAssertEqual(board.snapshot(for: .openai)?.status, .ok)
    }

    func testStaleFetchKeepsPreviousGoodEntry() async {
        let previous = UsageBoard(snapshots: [snap(.claude, limits: [limit(40)], fetchedAt: 100)])
        let providers: [any UsageProvider] = [
            StubUsageProvider(id: .claude, result: .success(
                snap(.claude, fetchedAt: 200, status: .stale(reason: "offline"))))
        ]
        let board = await UsageRefresher.refresh(previous, providers: providers)
        let claude = board.snapshot(for: .claude)
        XCTAssertEqual(claude?.limits, [limit(40)])
        XCTAssertEqual(claude?.fetchedAt, Date(timeIntervalSince1970: 100))
        XCTAssertEqual(claude?.status, .stale(reason: "offline"))
    }

    func testProvidersNotInListKeepTheirEntry() async {
        let previous = UsageBoard(snapshots: [snap(.openai, limits: [limit(5)], fetchedAt: 7)])
        let providers: [any UsageProvider] = [
            StubUsageProvider(id: .claude, result: .success(snap(.claude, limits: [limit(40)])))
        ]
        let board = await UsageRefresher.refresh(previous, providers: providers)
        XCTAssertEqual(board.snapshot(for: .openai)?.fetchedAt, Date(timeIntervalSince1970: 7))
        XCTAssertEqual(board.snapshots.count, 2)
    }

    func testProvidersRunConcurrently() async {
        let providers: [any UsageProvider] = [
            StubUsageProvider(id: .claude, result: .success(snap(.claude)), delay: 0.4),
            StubUsageProvider(id: .openai, result: .success(snap(.openai)), delay: 0.4)
        ]
        let start = Date()
        _ = await UsageRefresher.refresh(UsageBoard(), providers: providers)
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.7)
    }
}
