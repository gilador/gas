import XCTest
import Foundation
@testable import UsageCore

final class FileCodexAuthReaderTests: XCTestCase {
    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testMissingFileThrowsNotFound() throws {
        let reader = FileCodexAuthReader(fileURL: try tempDir().appendingPathComponent("auth.json"))
        XCTAssertThrowsError(try reader.readCodexAuth()) {
            XCTAssertEqual($0 as? TokenReaderError, .notFound)
        }
    }

    func testReadsValidFile() throws {
        let url = try tempDir().appendingPathComponent("auth.json")
        try Fixtures.data("codex_auth").write(to: url)
        let auth = try FileCodexAuthReader(fileURL: url).readCodexAuth()
        XCTAssertEqual(auth.accessToken, "fake.access.token")
    }

    func testBadFileThrowsMalformed() throws {
        let url = try tempDir().appendingPathComponent("auth.json")
        try "{".data(using: .utf8)!.write(to: url)
        XCTAssertThrowsError(try FileCodexAuthReader(fileURL: url).readCodexAuth()) {
            XCTAssertEqual($0 as? TokenReaderError, .malformed)
        }
    }

    func testDefaultURLEndsWithCodexAuthJSON() {
        XCTAssertEqual(FileCodexAuthReader.defaultURL.lastPathComponent, "auth.json")
        XCTAssertEqual(FileCodexAuthReader.defaultURL.deletingLastPathComponent().lastPathComponent, ".codex")
    }
}
