import XCTest
@testable import UsageCore

final class UsageSnapshotTests: XCTestCase {
    private func limit(_ id: String, _ pct: Double) -> UsageLimit {
        UsageLimit(id: id, label: id, percentUsed: pct, resetsAt: nil, severity: .normal)
    }

    func testTightestLimitPicksHighestPercent() {
        let snap = UsageSnapshot(
            provider: .claude, fetchedAt: Date(),
            limits: [limit("a", 40), limit("b", 88), limit("c", 12)], status: .ok)
        XCTAssertEqual(snap.tightestLimit?.id, "b")
    }

    func testTightestLimitNilWhenEmpty() {
        let snap = UsageSnapshot(provider: .claude, fetchedAt: Date(),
                                 limits: [], status: .needsSignIn)
        XCTAssertNil(snap.tightestLimit)
    }

    func testFetchStatusEquatable() {
        XCTAssertEqual(FetchStatus.stale(reason: "x"), .stale(reason: "x"))
        XCTAssertNotEqual(FetchStatus.stale(reason: "x"), .stale(reason: "y"))
        XCTAssertNotEqual(FetchStatus.ok, .needsSignIn)
    }

    private func snap(_ provider: ProviderID = .claude, limits: [UsageLimit],
                      fetchedAt: TimeInterval, status: FetchStatus) -> UsageSnapshot {
        UsageSnapshot(provider: provider, fetchedAt: Date(timeIntervalSince1970: fetchedAt),
                      limits: limits, status: status)
    }

    func testMergeStaleEmptyKeepsPreviousLimitsAndTimestamp() {
        let previous = snap(limits: [limit("session", 40)], fetchedAt: 100, status: .ok)
        let fetched = snap(limits: [], fetchedAt: 200, status: .stale(reason: "offline"))
        let merged = fetched.mergingLastGood(previous: previous)
        XCTAssertEqual(merged.limits, previous.limits)
        XCTAssertEqual(merged.fetchedAt, Date(timeIntervalSince1970: 100))
        XCTAssertEqual(merged.status, .stale(reason: "offline"))
    }

    func testMergeErrorEmptyKeepsPreviousLimits() {
        let previous = snap(limits: [limit("session", 40)], fetchedAt: 100, status: .ok)
        let fetched = snap(limits: [], fetchedAt: 200, status: .error(message: "HTTP 500"))
        XCTAssertEqual(fetched.mergingLastGood(previous: previous).limits, previous.limits)
    }

    func testMergeStaleWithPreviousEmptyReturnsSelf() {
        let previous = snap(limits: [], fetchedAt: 100, status: .needsSignIn)
        let fetched = snap(limits: [], fetchedAt: 200, status: .stale(reason: "x"))
        XCTAssertEqual(fetched.mergingLastGood(previous: previous), fetched)
    }

    func testMergeStaleWithNewLimitsReturnsSelf() {
        let previous = snap(limits: [limit("session", 40)], fetchedAt: 100, status: .ok)
        let fetched = snap(limits: [limit("session", 50)], fetchedAt: 200, status: .stale(reason: "x"))
        XCTAssertEqual(fetched.mergingLastGood(previous: previous), fetched)
    }

    func testMergeOkReturnsSelf() {
        let previous = snap(limits: [limit("session", 40)], fetchedAt: 100, status: .ok)
        let fetched = snap(limits: [], fetchedAt: 200, status: .ok)
        XCTAssertEqual(fetched.mergingLastGood(previous: previous), fetched)
    }

    func testMergeNeedsSignInAndKeychainDeniedReturnSelf() {
        let previous = snap(limits: [limit("session", 40)], fetchedAt: 100, status: .ok)
        for status in [FetchStatus.needsSignIn, .keychainDenied] {
            let fetched = snap(limits: [], fetchedAt: 200, status: status)
            XCTAssertEqual(fetched.mergingLastGood(previous: previous), fetched)
        }
    }

    func testMergeIgnoresPreviousOfOtherProvider() {
        let previous = snap(.openai, limits: [limit("session", 40)], fetchedAt: 100, status: .ok)
        let fetched = snap(.claude, limits: [], fetchedAt: 200, status: .stale(reason: "x"))
        XCTAssertEqual(fetched.mergingLastGood(previous: previous), fetched)
    }

    func testMergeWithNilPreviousReturnsSelf() {
        let fetched = snap(limits: [], fetchedAt: 200, status: .stale(reason: "x"))
        XCTAssertEqual(fetched.mergingLastGood(previous: nil), fetched)
    }

    func testRateLimitedStatusCodableRoundTrip() throws {
        let snap = UsageSnapshot(provider: .claude, fetchedAt: Date(timeIntervalSince1970: 1),
                                 limits: [], status: .rateLimited(until: Date(timeIntervalSince1970: 900), wait: 900))
        let data = try JSONEncoder().encode(snap)
        XCTAssertEqual(try JSONDecoder().decode(UsageSnapshot.self, from: data), snap)
    }

    func testMergeRateLimitedEmptyKeepsPreviousLimits() {
        let previous = snap(limits: [limit("session", 40)], fetchedAt: 100, status: .ok)
        let fetched = snap(limits: [], fetchedAt: 200,
                           status: .rateLimited(until: Date(timeIntervalSince1970: 1100), wait: 900))
        let merged = fetched.mergingLastGood(previous: previous)
        XCTAssertEqual(merged.limits, previous.limits)
        XCTAssertEqual(merged.fetchedAt, Date(timeIntervalSince1970: 100))
        XCTAssertEqual(merged.status, .rateLimited(until: Date(timeIntervalSince1970: 1100), wait: 900))
    }

    func testHeadlineIsTheMostUsedProviderWideLimit() {
        let snap = UsageSnapshot(provider: .openai, fetchedAt: Date(),
                                 limits: [limit("session", 0), limit("weekly_all", 100)], status: .ok)
        XCTAssertEqual(snap.headlineLimit?.id, "weekly_all")
    }

    func testHeadlineIgnoresPerModelLimits() {
        let snap = UsageSnapshot(provider: .claude, fetchedAt: Date(),
                                 limits: [limit("session", 40), limit("weekly_all", 60), limit("weekly_scoped#Fable", 95)],
                                 status: .ok)
        XCTAssertEqual(snap.headlineLimit?.id, "weekly_all")
    }

    func testHeadlineFallsBackToPerModelWhenAlone() {
        let snap = UsageSnapshot(provider: .claude, fetchedAt: Date(),
                                 limits: [limit("weekly_scoped#Fable", 30)], status: .ok)
        XCTAssertEqual(snap.headlineLimit?.id, "weekly_scoped#Fable")
    }

    func testHeadlineNilWithoutLimits() {
        XCTAssertNil(UsageSnapshot(provider: .claude, fetchedAt: Date(), limits: [], status: .ok).headlineLimit)
    }
}
