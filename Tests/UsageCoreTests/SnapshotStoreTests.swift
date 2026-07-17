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

    func testRoundTrip() throws {
        let store = SnapshotStore(containerURL: try tempDir())
        let limit = UsageLimit(id: "five_hour", label: "Session (5h)", percentUsed: 42,
                               resetsAt: Date(timeIntervalSince1970: 1000), severity: .normal)
        let snap = UsageSnapshot(provider: .claude,
                                 fetchedAt: Date(timeIntervalSince1970: 500),
                                 limits: [limit], status: .ok)
        try store.save(snap)
        let loaded = store.load()
        XCTAssertEqual(loaded?.provider, .claude)
        XCTAssertEqual(loaded?.fetchedAt, Date(timeIntervalSince1970: 500))
        XCTAssertEqual(loaded?.limits.first?.id, "five_hour")
        XCTAssertEqual(loaded?.limits.first?.percentUsed, 42)
        XCTAssertEqual(loaded?.status, .ok)
    }

    func testLoadReturnsNilWhenMissing() throws {
        let store = SnapshotStore(containerURL: try tempDir())
        XCTAssertNil(store.load())
    }

    func testAppGroupInitFallsBackWithoutEntitlement() {
        // No App Group entitlement in `swift test`; must not crash and must be usable.
        let store = SnapshotStore(appGroupID: "group.com.gilad.agentusage")
        XCTAssertNil(store.load())
    }
}
