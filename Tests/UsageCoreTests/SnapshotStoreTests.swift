import XCTest
import Foundation
@testable import UsageCore

final class SnapshotStoreTests: XCTestCase {
    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func limit(_ id: String, _ pct: Double) -> UsageLimit {
        UsageLimit(id: id, label: id, percentUsed: pct,
                   resetsAt: Date(timeIntervalSince1970: 1000), severity: .normal)
    }

    func testBoardRoundTrip() throws {
        let store = SnapshotStore(containerURL: try tempDir())
        let board = UsageBoard(snapshots: [
            UsageSnapshot(provider: .claude, fetchedAt: Date(timeIntervalSince1970: 500),
                          limits: [limit("session", 42)], status: .ok),
            UsageSnapshot(provider: .openai, fetchedAt: Date(timeIntervalSince1970: 600),
                          limits: [], status: .stale(reason: "offline"))
        ])
        try store.save(board)
        XCTAssertEqual(store.load(), board)
    }

    func testCorruptFileLoadsNil() throws {
        let dir = try tempDir()
        try "not json".data(using: .utf8)!.write(to: dir.appendingPathComponent("usage_board.json"))
        XCTAssertNil(SnapshotStore(containerURL: dir).load())
    }

    func testLegacySingleSnapshotFileIsIgnored() throws {
        let dir = try tempDir()
        let legacy = UsageSnapshot(provider: .claude, fetchedAt: Date(), limits: [], status: .ok)
        try JSONEncoder().encode(legacy).write(to: dir.appendingPathComponent("usage_snapshot.json"))
        XCTAssertNil(SnapshotStore(containerURL: dir).load())
    }

    func testLoadReturnsNilWhenMissing() throws {
        let store = SnapshotStore(containerURL: try tempDir())
        XCTAssertNil(store.load())
    }

    func testAppGroupInitFallsBackWithoutEntitlement() throws {
        // `containerURL(forSecurityApplicationGroupIdentifier:)` blocks indefinitely in an
        // unentitled `swift test` process, so this real-App-Group path is opt-in only.
        // The properly entitled app/widget targets resolve the container without blocking.
        guard ProcessInfo.processInfo.environment["RUN_APP_GROUP_INTEGRATION_TESTS"] != nil else {
            throw XCTSkip("Set RUN_APP_GROUP_INTEGRATION_TESTS=1 to exercise the real App Group container")
        }
        let store = SnapshotStore(appGroupID: "group.com.gilad.agentusage")
        XCTAssertNil(store.load())
    }
}
