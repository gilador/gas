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

    private func writeLegacy(_ snapshot: UsageSnapshot, in dir: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(snapshot).write(to: dir.appendingPathComponent("usage_snapshot.json"))
    }

    func testLegacySnapshotIsImportedWhenBoardLacksProvider() throws {
        let dir = try tempDir()
        let store = SnapshotStore(containerURL: dir)
        let openai = UsageSnapshot(provider: .openai, fetchedAt: Date(timeIntervalSince1970: 900),
                                   limits: [limit("session", 46)], status: .ok)
        try store.save(UsageBoard(snapshots: [openai]))
        let legacy = UsageSnapshot(provider: .claude, fetchedAt: Date(timeIntervalSince1970: 500),
                                   limits: [limit("session", 61)], status: .stale(reason: "old"))
        try writeLegacy(legacy, in: dir)
        let board = store.load()
        XCTAssertEqual(board?.snapshots.map(\.provider), [.claude, .openai])
        XCTAssertEqual(board?.snapshot(for: .claude), legacy)
        XCTAssertEqual(board?.snapshot(for: .openai), openai)
    }

    func testLegacySnapshotIsIgnoredWhenBoardHasProvider() throws {
        let dir = try tempDir()
        let store = SnapshotStore(containerURL: dir)
        let current = UsageSnapshot(provider: .claude, fetchedAt: Date(timeIntervalSince1970: 900),
                                    limits: [limit("session", 10)], status: .ok)
        try store.save(UsageBoard(snapshots: [current]))
        try writeLegacy(UsageSnapshot(provider: .claude, fetchedAt: Date(timeIntervalSince1970: 500),
                                      limits: [limit("session", 61)], status: .ok), in: dir)
        XCTAssertEqual(store.load()?.snapshot(for: .claude), current)
    }

    func testLegacySnapshotAloneYieldsBoard() throws {
        let dir = try tempDir()
        let legacy = UsageSnapshot(provider: .claude, fetchedAt: Date(timeIntervalSince1970: 500),
                                   limits: [limit("session", 61)], status: .ok)
        try writeLegacy(legacy, in: dir)
        XCTAssertEqual(SnapshotStore(containerURL: dir).load(), UsageBoard(snapshots: [legacy]))
    }

    func testCorruptLegacyIsIgnored() throws {
        let dir = try tempDir()
        try "nope".data(using: .utf8)!.write(to: dir.appendingPathComponent("usage_snapshot.json"))
        XCTAssertNil(SnapshotStore(containerURL: dir).load())
    }

    func testLegacyFileIsNotModified() throws {
        let dir = try tempDir()
        try writeLegacy(UsageSnapshot(provider: .claude, fetchedAt: Date(timeIntervalSince1970: 500),
                                      limits: [], status: .ok), in: dir)
        let url = dir.appendingPathComponent("usage_snapshot.json")
        let before = try Data(contentsOf: url)
        _ = SnapshotStore(containerURL: dir).load()
        XCTAssertEqual(try Data(contentsOf: url), before)
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
