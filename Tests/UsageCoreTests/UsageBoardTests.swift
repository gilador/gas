import XCTest
import Foundation
@testable import UsageCore

final class UsageBoardTests: XCTestCase {
    private func limit(_ id: String, _ pct: Double) -> UsageLimit {
        UsageLimit(id: id, label: id, percentUsed: pct, resetsAt: nil, severity: .normal)
    }
    private func snap(_ provider: ProviderID, limits: [UsageLimit] = [],
                      fetchedAt: TimeInterval = 0, status: FetchStatus = .ok) -> UsageSnapshot {
        UsageSnapshot(provider: provider, fetchedAt: Date(timeIntervalSince1970: fetchedAt),
                      limits: limits, status: status)
    }

    func testEmptyBoard() {
        let board = UsageBoard()
        XCTAssertTrue(board.isEmpty)
        XCTAssertTrue(board.snapshots.isEmpty)
        XCTAssertNil(board.snapshot(for: .claude))
        XCTAssertTrue(board.tightestLimits.isEmpty)
        XCTAssertNil(board.latestFetchedAt)
    }

    func testReplaceKeepsDisplayOrderRegardlessOfInsertOrder() {
        var board = UsageBoard()
        board.replace(snap(.openai))
        board.replace(snap(.claude))
        XCTAssertEqual(board.snapshots.map(\.provider), [.claude, .openai])
        XCTAssertFalse(board.isEmpty)
    }

    func testInitSortsSnapshots() {
        let board = UsageBoard(snapshots: [snap(.openai), snap(.claude)])
        XCTAssertEqual(board.snapshots.map(\.provider), [.claude, .openai])
    }

    func testReplaceOverwritesSameProvider() {
        var board = UsageBoard(snapshots: [snap(.claude, fetchedAt: 1)])
        board.replace(snap(.claude, fetchedAt: 2))
        XCTAssertEqual(board.snapshots.count, 1)
        XCTAssertEqual(board.snapshot(for: .claude)?.fetchedAt, Date(timeIntervalSince1970: 2))
    }

    func testSnapshotForProvider() {
        let board = UsageBoard(snapshots: [snap(.claude), snap(.openai, fetchedAt: 9)])
        XCTAssertEqual(board.snapshot(for: .openai)?.fetchedAt, Date(timeIntervalSince1970: 9))
        XCTAssertNil(board.snapshot(for: .xai))
    }

    func testTightestLimitsOnePerProviderSkippingEmpty() {
        let board = UsageBoard(snapshots: [
            snap(.claude, limits: [limit("session", 40), limit("weekly_all", 88)]),
            snap(.openai, status: .needsSignIn)
        ])
        XCTAssertEqual(board.tightestLimits,
                       [ProviderLimit(provider: .claude, limit: limit("weekly_all", 88))])
    }

    func testTightestLimitsFollowsDisplayOrder() {
        let board = UsageBoard(snapshots: [
            snap(.openai, limits: [limit("session", 52)]),
            snap(.claude, limits: [limit("session", 42)])
        ])
        XCTAssertEqual(board.tightestLimits.map(\.provider), [.claude, .openai])
    }

    func testLatestFetchedAtIsNewest() {
        let board = UsageBoard(snapshots: [snap(.claude, fetchedAt: 100), snap(.openai, fetchedAt: 300)])
        XCTAssertEqual(board.latestFetchedAt, Date(timeIntervalSince1970: 300))
    }

    func testCodableRoundTrip() throws {
        let board = UsageBoard(snapshots: [
            snap(.claude, limits: [limit("session", 40)], fetchedAt: 5),
            snap(.openai, fetchedAt: 6, status: .stale(reason: "x"))
        ])
        let data = try JSONEncoder().encode(board)
        let decoded = try JSONDecoder().decode(UsageBoard.self, from: data)
        XCTAssertEqual(decoded, board)
    }

    func testLastRequestDefaultsToNil() {
        let board = UsageBoard()
        XCTAssertNil(board.lastRequest(for: .claude))
    }

    func testMarkRequestedIsPerProvider() {
        var board = UsageBoard()
        let stamp = Date(timeIntervalSince1970: 42)
        board.markRequested(.claude, at: stamp)
        XCTAssertEqual(board.lastRequest(for: .claude), stamp)
        XCTAssertNil(board.lastRequest(for: .openai))
    }

    func testCodableRoundTripKeepsLastRequestStamp() throws {
        var board = UsageBoard(snapshots: [snap(.claude, fetchedAt: 5)])
        board.markRequested(.claude, at: Date(timeIntervalSince1970: 42))
        let data = try JSONEncoder().encode(board)
        let decoded = try JSONDecoder().decode(UsageBoard.self, from: data)
        XCTAssertEqual(decoded, board)
        XCTAssertEqual(decoded.lastRequest(for: .claude), Date(timeIntervalSince1970: 42))
    }

    func testDecodingBoardWithoutLastRequestsKeyHasNoStamps() throws {
        let data = #"{"snapshots":[]}"#.data(using: .utf8)!
        let board = try JSONDecoder().decode(UsageBoard.self, from: data)
        XCTAssertNil(board.lastRequest(for: .claude))
        XCTAssertNil(board.lastRequest(for: .openai))
    }

    func testReplaceDoesNotTouchStamps() {
        var board = UsageBoard()
        let stamp = Date(timeIntervalSince1970: 42)
        board.markRequested(.claude, at: stamp)
        board.replace(snap(.claude, fetchedAt: 9))
        XCTAssertEqual(board.lastRequest(for: .claude), stamp)
    }
}
