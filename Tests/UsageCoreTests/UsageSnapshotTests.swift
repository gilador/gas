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
}
