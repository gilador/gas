import Foundation
import XCTest
@testable import UsageCore

final class RefreshScheduleTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 10_000)

    private func provider(_ id: ProviderID, manualInterval: TimeInterval = 60) -> CountingUsageProvider {
        CountingUsageProvider(id: id, result: .success(
            UsageSnapshot(provider: id, fetchedAt: now, limits: [], status: .ok)),
            minimumInterval: 270, manualMinimumInterval: manualInterval)
    }

    func testManualRefreshIsAvailableWhenAnyEnabledProviderCanFetch() {
        var board = UsageBoard()
        board.markRequested(.xai, at: now)
        let date = UsageRefresher.nextRefreshDate(board, providers: [provider(.openai), provider(.xai, manualInterval: 270)],
                                                 now: now, manual: true)
        XCTAssertEqual(date, now)
    }

    func testManualRefreshWaitsForTheSoonestProvider() {
        var board = UsageBoard()
        board.markRequested(.openai, at: now.addingTimeInterval(-30))
        board.markRequested(.xai, at: now)
        let date = UsageRefresher.nextRefreshDate(board, providers: [provider(.openai), provider(.xai, manualInterval: 270)],
                                                 now: now, manual: true)
        XCTAssertEqual(date, now.addingTimeInterval(30))
    }

    func testReconnectKeepsTheAutomaticRequestFloor() async {
        var board = UsageBoard()
        board.markRequested(.openai, at: now.addingTimeInterval(-30))
        let codex = provider(.openai)
        let date = UsageRefresher.nextRequestDate(board, provider: codex, now: now)
        XCTAssertEqual(date, now.addingTimeInterval(240))
        _ = await UsageRefresher.refresh(board, providers: [codex], now: now)
        XCTAssertEqual(codex.calls, 0)
        _ = await UsageRefresher.refresh(board, providers: [codex], now: date)
        XCTAssertEqual(codex.calls, 1)
    }

    func testRateLimitWaitSurvivesAReconnectAndManualRefresh() async {
        var board = UsageBoard(snapshots: [
            UsageSnapshot(provider: .openai, fetchedAt: now, limits: [],
                          status: .rateLimited(until: now.addingTimeInterval(900), wait: 900))
        ])
        board.markRequested(.openai, at: now)
        let codex = provider(.openai)
        for manual in [false, true] {
            let date = UsageRefresher.nextRequestDate(board, provider: codex, now: now, manual: manual)
            XCTAssertEqual(date, now.addingTimeInterval(900))
            let calls = codex.calls
            _ = await UsageRefresher.refresh(board, providers: [codex], now: now, manual: manual)
            XCTAssertEqual(codex.calls, calls)
            _ = await UsageRefresher.refresh(board, providers: [codex], now: date, manual: manual)
        }
        XCTAssertEqual(codex.calls, 2)
    }

    func testRateLimitEndingBeforeTheRequestFloorStillWaitsForTheFloor() {
        var board = UsageBoard(snapshots: [
            UsageSnapshot(provider: .openai, fetchedAt: now, limits: [],
                          status: .rateLimited(until: now.addingTimeInterval(10), wait: 10))
        ])
        board.markRequested(.openai, at: now)
        XCTAssertEqual(UsageRefresher.nextRequestDate(board, provider: provider(.openai), now: now),
                       now.addingTimeInterval(270))
    }

    func testNoEnabledProvidersHaveNoRefreshDeadline() {
        XCTAssertNil(UsageRefresher.nextRefreshDate(UsageBoard(), providers: [], now: now, manual: true))
    }
}
