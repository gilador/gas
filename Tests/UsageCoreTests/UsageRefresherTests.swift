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

    private let now = Date(timeIntervalSince1970: 10_000)

    func testRateLimitedProviderIsSkippedUntilDeadline() async {
        let previous = UsageBoard(snapshots: [
            snap(.claude, limits: [limit(40)], fetchedAt: 100,
                status: .rateLimited(until: now.addingTimeInterval(60), wait: 900))
        ])
        let claude = CountingUsageProvider(id: .claude, result: .success(snap(.claude, limits: [limit(99)])))
        let openai = CountingUsageProvider(id: .openai, result: .success(snap(.openai, limits: [limit(50)])))
        let board = await UsageRefresher.refresh(previous, providers: [claude, openai], now: now)
        XCTAssertEqual(claude.calls, 0)
        XCTAssertEqual(board.snapshot(for: .claude)?.status,
                       .rateLimited(until: now.addingTimeInterval(60), wait: 900))
        XCTAssertEqual(board.snapshot(for: .claude)?.limits, [limit(40)])
        XCTAssertEqual(openai.calls, 1)
    }

    func testRateLimitedProviderIsFetchedAfterDeadline() async {
        let previous = UsageBoard(snapshots: [
            snap(.claude, limits: [limit(40)], fetchedAt: 100,
                status: .rateLimited(until: now.addingTimeInterval(-1), wait: 900))
        ])
        let claude = CountingUsageProvider(id: .claude, result: .success(snap(.claude, limits: [limit(99)])))
        _ = await UsageRefresher.refresh(previous, providers: [claude], now: now)
        XCTAssertEqual(claude.calls, 1)
    }

    func testRateLimitedFetchAppliesPolicyAndKeepsLimits() async {
        let previous = UsageBoard(snapshots: [snap(.claude, limits: [limit(40)], fetchedAt: 100, status: .ok)])
        let claude = CountingUsageProvider(id: .claude, result: .success(
            snap(.claude, fetchedAt: 10_000, status: .rateLimited(until: now, wait: 0))))
        let board = await UsageRefresher.refresh(previous, providers: [claude], now: now)
        XCTAssertEqual(board.snapshot(for: .claude)?.status,
                       .rateLimited(until: Date(timeIntervalSince1970: 10_000).addingTimeInterval(900), wait: 900))
        XCTAssertEqual(board.snapshot(for: .claude)?.limits, [limit(40)])
        XCTAssertEqual(board.snapshot(for: .claude)?.fetchedAt, Date(timeIntervalSince1970: 100))
    }

    func testRepeatedRateLimitDoubles() async {
        let previous = UsageBoard(snapshots: [
            snap(.claude, limits: [limit(40)], fetchedAt: 100,
                status: .rateLimited(until: now.addingTimeInterval(-1), wait: 900))
        ])
        let claude = CountingUsageProvider(id: .claude, result: .success(
            snap(.claude, fetchedAt: 10_000, status: .rateLimited(until: now, wait: 0))))
        let board = await UsageRefresher.refresh(previous, providers: [claude], now: now)
        guard case .rateLimited(_, let wait) = board.snapshot(for: .claude)?.status else {
            return XCTFail("expected .rateLimited")
        }
        XCTAssertEqual(wait, 1800)
    }

    func testServerRetryAfterWinsInRefresher() async {
        let previous = UsageBoard(snapshots: [
            snap(.claude, limits: [limit(40)], fetchedAt: 100,
                status: .rateLimited(until: now.addingTimeInterval(-1), wait: 3600))
        ])
        let claude = CountingUsageProvider(id: .claude, result: .success(
            snap(.claude, fetchedAt: 10_000, status: .rateLimited(until: now, wait: 850))))
        let board = await UsageRefresher.refresh(previous, providers: [claude], now: now)
        guard case .rateLimited(_, let wait) = board.snapshot(for: .claude)?.status else {
            return XCTFail("expected .rateLimited")
        }
        XCTAssertEqual(wait, 850)
    }

    func testProviderInsideMinimumIntervalIsSkipped() async {
        var previous = UsageBoard(snapshots: [snap(.claude, limits: [limit(40)], fetchedAt: 100)])
        previous.markRequested(.claude, at: now.addingTimeInterval(-1800))
        let claude = CountingUsageProvider(id: .claude, result: .success(snap(.claude, limits: [limit(99)])),
                                           minimumInterval: 3600)
        let board = await UsageRefresher.refresh(previous, providers: [claude], now: now)
        XCTAssertEqual(claude.calls, 0)
        XCTAssertEqual(board.snapshot(for: .claude)?.limits, [limit(40)])
        XCTAssertEqual(board.lastRequest(for: .claude), now.addingTimeInterval(-1800))
    }

    func testProviderPastMinimumIntervalIsFetchedAndStamped() async {
        var previous = UsageBoard(snapshots: [snap(.claude, limits: [limit(40)], fetchedAt: 100)])
        previous.markRequested(.claude, at: now.addingTimeInterval(-3600))
        let claude = CountingUsageProvider(id: .claude, result: .success(snap(.claude, limits: [limit(99)])),
                                           minimumInterval: 3600)
        let board = await UsageRefresher.refresh(previous, providers: [claude], now: now)
        XCTAssertEqual(claude.calls, 1)
        XCTAssertEqual(board.snapshot(for: .claude)?.limits, [limit(99)])
        XCTAssertEqual(board.lastRequest(for: .claude), now)
    }

    func testFirstRequestIsAlwaysAllowed() async {
        let claude = CountingUsageProvider(id: .claude, result: .success(snap(.claude, limits: [limit(99)])),
                                           minimumInterval: 3600)
        let board = await UsageRefresher.refresh(UsageBoard(), providers: [claude], now: now)
        XCTAssertEqual(claude.calls, 1)
        XCTAssertEqual(board.lastRequest(for: .claude), now)
    }

    func testZeroIntervalProviderIsFetchedEveryTime() async {
        var previous = UsageBoard()
        previous.markRequested(.claude, at: now)
        let claude = CountingUsageProvider(id: .claude, result: .success(snap(.claude, limits: [limit(99)])))
        let board = await UsageRefresher.refresh(previous, providers: [claude], now: now)
        XCTAssertEqual(claude.calls, 1)
        XCTAssertEqual(board.lastRequest(for: .claude), now)
    }

    func testRateLimitedFetchIsStampedToo() async {
        let claude = CountingUsageProvider(id: .claude, result: .success(
            snap(.claude, fetchedAt: 10_000, status: .rateLimited(until: now, wait: 850))))
        let board = await UsageRefresher.refresh(UsageBoard(), providers: [claude], now: now)
        XCTAssertEqual(board.lastRequest(for: .claude), now)
    }

    func testKeychainDeniedIsNotStamped() async {
        let claude = CountingUsageProvider(id: .claude, result: .success(
            snap(.claude, status: .keychainDenied)), minimumInterval: 3600)
        claude.requestSent = false
        let board = await UsageRefresher.refresh(UsageBoard(), providers: [claude], now: now)
        XCTAssertNil(board.lastRequest(for: .claude))
    }

    func testNeedsSignInIsNotStamped() async {
        let claude = CountingUsageProvider(id: .claude, result: .success(
            snap(.claude, status: .needsSignIn)), minimumInterval: 3600)
        claude.requestSent = false
        let board = await UsageRefresher.refresh(UsageBoard(), providers: [claude], now: now)
        XCTAssertNil(board.lastRequest(for: .claude))
    }

    func testOkIsStamped() async {
        let claude = CountingUsageProvider(id: .claude, result: .success(snap(.claude)),
                                           minimumInterval: 3600)
        let board = await UsageRefresher.refresh(UsageBoard(), providers: [claude], now: now)
        XCTAssertEqual(board.lastRequest(for: .claude), now)
    }

    func testManualRefreshWithinDebounceIsSkipped() async {
        var previous = UsageBoard()
        previous.markRequested(.openai, at: now.addingTimeInterval(-30))
        let openai = CountingUsageProvider(id: .openai, result: .success(snap(.openai)),
                                           minimumInterval: 0, manualMinimumInterval: 60)
        _ = await UsageRefresher.refresh(previous, providers: [openai], now: now, manual: true)
        XCTAssertEqual(openai.calls, 0)
    }

    func testManualRefreshAfterDebounceIsFetched() async {
        var previous = UsageBoard()
        previous.markRequested(.openai, at: now.addingTimeInterval(-61))
        let openai = CountingUsageProvider(id: .openai, result: .success(snap(.openai)),
                                           minimumInterval: 0, manualMinimumInterval: 60)
        let board = await UsageRefresher.refresh(previous, providers: [openai], now: now, manual: true)
        XCTAssertEqual(openai.calls, 1)
        XCTAssertEqual(board.lastRequest(for: .openai), now)
    }

    func testManualRefreshRespectsClaudeHour() async {
        var previous = UsageBoard()
        previous.markRequested(.claude, at: now.addingTimeInterval(-1800))
        let claude = CountingUsageProvider(id: .claude, result: .success(snap(.claude)),
                                           minimumInterval: 3600, manualMinimumInterval: 3600)
        _ = await UsageRefresher.refresh(previous, providers: [claude], now: now, manual: true)
        XCTAssertEqual(claude.calls, 0)
    }

    func testAutomaticRefreshIgnoresDebounce() async {
        var previous = UsageBoard()
        previous.markRequested(.openai, at: now.addingTimeInterval(-30))
        let openai = CountingUsageProvider(id: .openai, result: .success(snap(.openai)),
                                           minimumInterval: 0, manualMinimumInterval: 60)
        _ = await UsageRefresher.refresh(previous, providers: [openai], now: now, manual: false)
        XCTAssertEqual(openai.calls, 1)
    }

    func testManualRefreshStillHonorsRateLimitDeadline() async {
        let previous = UsageBoard(snapshots: [
            snap(.claude, fetchedAt: 100, status: .rateLimited(until: now.addingTimeInterval(60), wait: 900))
        ])
        let claude = CountingUsageProvider(id: .claude, result: .success(snap(.claude)))
        _ = await UsageRefresher.refresh(previous, providers: [claude], now: now, manual: true)
        XCTAssertEqual(claude.calls, 0)
    }

    private func rateLimitedClaude(fingerprint: String?) -> CountingUsageProvider {
        let claude = CountingUsageProvider(id: .claude, result: .success(
            snap(.claude, fetchedAt: 10_000, status: .rateLimited(until: now, wait: 1555))),
                                           minimumInterval: 270)
        claude.fingerprint = fingerprint
        claude.sentFingerprint = fingerprint
        return claude
    }

    func testRateLimitWaitEndsWhenTheCredentialChanges() async {
        let claude = rateLimitedClaude(fingerprint: "old")
        let limited = await UsageRefresher.refresh(UsageBoard(), providers: [claude], now: now)
        claude.fingerprint = "new"
        _ = await UsageRefresher.refresh(limited, providers: [claude], now: now.addingTimeInterval(60))
        XCTAssertEqual(claude.calls, 2)
    }

    func testRateLimitWaitHoldsWhenTheCredentialIsTheSame() async {
        let claude = rateLimitedClaude(fingerprint: "same")
        let limited = await UsageRefresher.refresh(UsageBoard(), providers: [claude], now: now)
        _ = await UsageRefresher.refresh(limited, providers: [claude], now: now.addingTimeInterval(600))
        XCTAssertEqual(claude.calls, 1)
    }

    func testRateLimitWaitHoldsWhenTheCredentialIsUnknown() async {
        let claude = rateLimitedClaude(fingerprint: nil)
        let limited = await UsageRefresher.refresh(UsageBoard(), providers: [claude], now: now)
        claude.fingerprint = "new"
        _ = await UsageRefresher.refresh(limited, providers: [claude], now: now.addingTimeInterval(600))
        XCTAssertEqual(claude.calls, 1)
    }

    func testCredentialFingerprintIsNotSaved() async throws {
        let claude = rateLimitedClaude(fingerprint: "fp-4f2a")
        let limited = await UsageRefresher.refresh(UsageBoard(), providers: [claude], now: now)
        let json = String(decoding: try JSONEncoder().encode(limited), as: UTF8.self)
        XCTAssertFalse(json.contains("fp-4f2a"))
    }

    func testARejectedCredentialIsStampedAndNotResentBeforeTheInterval() async {
        let claude = CountingUsageProvider(id: .claude, result: .success(snap(.claude, status: .needsSignIn)),
                                           minimumInterval: 270)
        let rejected = await UsageRefresher.refresh(UsageBoard(), providers: [claude], now: now)
        XCTAssertEqual(rejected.lastRequest(for: .claude), now)
        _ = await UsageRefresher.refresh(rejected, providers: [claude], now: now.addingTimeInterval(60))
        _ = await UsageRefresher.refresh(rejected, providers: [claude], now: now.addingTimeInterval(30), manual: true)
        XCTAssertEqual(claude.calls, 1)
    }

    func testAnUnauthorizedResponseIsNotRetriedBeforeTheInterval() async {
        let openai = CountingUsageProvider(id: .openai, result: .success(
            snap(.openai, status: .stale(reason: "Unauthorized"))), minimumInterval: 270)
        let first = await UsageRefresher.refresh(UsageBoard(), providers: [openai], now: now)
        _ = await UsageRefresher.refresh(first, providers: [openai], now: now.addingTimeInterval(269))
        XCTAssertEqual(openai.calls, 1)
        _ = await UsageRefresher.refresh(first, providers: [openai], now: now.addingTimeInterval(270))
        XCTAssertEqual(openai.calls, 2)
    }

    func testAThrowingFetchStillCounts() async {
        let claude = CountingUsageProvider(id: .claude, result: .failure(StubError()), minimumInterval: 270)
        let board = await UsageRefresher.refresh(UsageBoard(), providers: [claude], now: now)
        XCTAssertEqual(board.lastRequest(for: .claude), now)
    }

    func testTheWaitBelongsToTheAccountThatWasSent() async {
        let codex = rateLimitedClaude(fingerprint: "acct-B")
        codex.sentFingerprint = "acct-A"
        let limited = await UsageRefresher.refresh(UsageBoard(), providers: [codex], now: now)
        _ = await UsageRefresher.refresh(limited, providers: [codex], now: now.addingTimeInterval(600))
        XCTAssertEqual(codex.calls, 2)
    }

    func testATokenRotationWithoutAnAccountDoesNotEndTheWait() async {
        let claude = rateLimitedClaude(fingerprint: nil)
        let limited = await UsageRefresher.refresh(UsageBoard(), providers: [claude], now: now)
        _ = await UsageRefresher.refresh(limited, providers: [claude], now: now.addingTimeInterval(600))
        XCTAssertEqual(claude.calls, 1)
    }

    func testTheRejectedCredentialKeepsTheLastGoodValues() async {
        let previous = UsageBoard(snapshots: [snap(.claude, limits: [limit(40)], fetchedAt: 100)])
        let claude = CountingUsageProvider(id: .claude, result: .success(
            snap(.claude, fetchedAt: 200, status: .needsSignIn)))
        let board = await UsageRefresher.refresh(previous, providers: [claude], now: now)
        XCTAssertEqual(board.snapshot(for: .claude)?.limits, [limit(40)])
        XCTAssertEqual(board.snapshot(for: .claude)?.status, .needsSignIn)
    }
}
