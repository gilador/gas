import XCTest
import Foundation
@testable import UsageCore

final class GrokAuthReaderTests: XCTestCase {
    private let entryKey = "https://auth.x.ai::b1a00492-073a-47ea-816f-4c329264a828"
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private var authURL: URL { dir.appendingPathComponent("auth.json") }

    private func reader(_ url: URL? = nil) -> FileGrokAuthReader {
        FileGrokAuthReader(fileURL: url ?? authURL, retryDelay: 0)
    }

    private func write(_ data: Data, mode: Int = 0o600) throws {
        try data.write(to: authURL)
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: authURL.path)
    }

    private func write(_ text: String, mode: Int = 0o600) throws {
        try write(Data(text.utf8), mode: mode)
    }

    private func entry(key: String = "SECRET-MARKER-1", expiresAt: String = "2026-01-05T15:55:50.809713Z",
                       userID: String = "user-placeholder-1") -> String {
        #"{"key":"\#(key)","expires_at":"\#(expiresAt)","user_id":"\#(userID)","refresh_token":"SECRET-MARKER-REFRESH"}"#
    }

    private func assertThrows(_ expected: GrokAuthError, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try reader().readGrokAuth(), file: file, line: line) {
            XCTAssertEqual($0 as? GrokAuthError, expected, file: file, line: line)
        }
    }

    func testReadsTheGrokCLIEntry() throws {
        try write(try Fixtures.data("grok_auth"))
        let auth = try reader().readGrokAuth()
        XCTAssertEqual(auth.accessToken, "SECRET-MARKER-1")
        XCTAssertEqual(auth.expiresAt.timeIntervalSince1970,
                       ISO8601DateFormatter().date(from: "2026-01-05T15:55:50Z")!.timeIntervalSince1970 + 0.809713,
                       accuracy: 0.001)
        XCTAssertEqual(auth.accountFingerprint.count, 64)
    }

    func testMissingFileIsNotFound() {
        assertThrows(.notFound)
    }

    func testSymlinkIsUnreadable() throws {
        let target = dir.appendingPathComponent("real.json")
        try Fixtures.data("grok_auth").write(to: target)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
        try FileManager.default.createSymbolicLink(at: authURL, withDestinationURL: target)
        assertThrows(.unreadable)
    }

    func testGroupReadableFileIsUnreadable() throws {
        try write(try Fixtures.data("grok_auth"), mode: 0o640)
        assertThrows(.unreadable)
    }

    func testWorldReadableFileIsUnreadable() throws {
        try write(try Fixtures.data("grok_auth"), mode: 0o604)
        assertThrows(.unreadable)
    }

    func testDirectoryIsUnreadable() throws {
        try FileManager.default.createDirectory(at: authURL, withIntermediateDirectories: false)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: authURL.path)
        assertThrows(.unreadable)
    }

    func testOversizedFileIsUnreadable() throws {
        let padding = String(repeating: " ", count: 64 * 1024)
        try write(#"{"\#(entryKey)":\#(entry())}"# + padding)
        assertThrows(.unreadable)
    }

    func testEmptyFileIsUnreadableAfterRetries() throws {
        try write("")
        assertThrows(.unreadable)
    }

    func testMalformedJSONIsMalformed() throws {
        try write("{")
        assertThrows(.malformed)
    }

    func testTopLevelArrayIsMalformed() throws {
        try write("[]")
        assertThrows(.malformed)
    }

    func testAnotherIssuerOnlyIsNotFound() throws {
        try write(#"{"https://auth.example.com::b1a00492-073a-47ea-816f-4c329264a828":\#(entry())}"#)
        assertThrows(.notFound)
    }

    func testAnotherClientOnlyIsNotFound() throws {
        try write(#"{"https://auth.x.ai::00000000-0000-4000-8000-000000000000":\#(entry())}"#)
        assertThrows(.notFound)
    }

    func testDuplicateEntryIsAmbiguous() throws {
        try write(#"{"\#(entryKey)":\#(entry()),"\#(entryKey)":\#(entry(userID: "user-placeholder-2"))}"#)
        assertThrows(.ambiguous)
    }

    func testTwoSpellingsOfTheIssuerAreAmbiguous() throws {
        try write(#"{"\#(entryKey)":\#(entry()),"https://auth.x.ai/::b1a00492-073a-47ea-816f-4c329264a828":\#(entry(userID: "user-placeholder-2"))}"#)
        assertThrows(.ambiguous)
    }

    func testOtherEntriesAreIgnored() throws {
        try write(#"{"https://auth.example.com::other":{"anything":[1,2,3]},"\#(entryKey)":\#(entry())}"#)
        XCTAssertEqual(try reader().readGrokAuth().accessToken, "SECRET-MARKER-1")
    }

    func testKeyWithLineBreakIsMalformed() throws {
        try write(#"{"\#(entryKey)":\#(entry(key: #"SECRET-MARKER-1\r\nX-Injected: 1"#))}"#)
        assertThrows(.malformed)
    }

    func testKeyWithControlCharacterIsMalformed() throws {
        try write(#"{"\#(entryKey)":\#(entry(key: #"SECRET\u0000MARKER"#))}"#)
        assertThrows(.malformed)
    }

    func testEmptyKeyIsMalformed() throws {
        try write(#"{"\#(entryKey)":\#(entry(key: ""))}"#)
        assertThrows(.malformed)
    }

    func testOverlongKeyIsMalformed() throws {
        try write(#"{"\#(entryKey)":\#(entry(key: String(repeating: "A", count: 4097)))}"#)
        assertThrows(.malformed)
    }

    func testLongestAllowedKeyIsRead() throws {
        try write(#"{"\#(entryKey)":\#(entry(key: String(repeating: "A", count: 4096)))}"#)
        XCTAssertEqual(try reader().readGrokAuth().accessToken.count, 4096)
    }

    func testMissingExpiryIsMalformed() throws {
        try write(#"{"\#(entryKey)":{"key":"SECRET-MARKER-1","user_id":"user-placeholder-1"}}"#)
        assertThrows(.malformed)
    }

    func testBadExpiryIsMalformed() throws {
        try write(#"{"\#(entryKey)":\#(entry(expiresAt: "next tuesday"))}"#)
        assertThrows(.malformed)
    }

    func testExpiryWithoutFractionIsRead() throws {
        try write(#"{"\#(entryKey)":\#(entry(expiresAt: "2026-01-05T15:55:50Z"))}"#)
        XCTAssertEqual(try reader().readGrokAuth().expiresAt, ISO8601DateFormatter().date(from: "2026-01-05T15:55:50Z"))
    }

    func testFingerprintSurvivesATokenRefresh() throws {
        try write(#"{"\#(entryKey)":\#(entry())}"#)
        let before = try reader().readGrokAuth().accountFingerprint
        try write(#"{"\#(entryKey)":\#(entry(key: "SECRET-MARKER-2", expiresAt: "2026-01-05T21:55:50.000001Z"))}"#)
        XCTAssertEqual(try reader().readGrokAuth().accountFingerprint, before)
    }

    func testFingerprintChangesWithTheAccount() throws {
        try write(#"{"\#(entryKey)":\#(entry())}"#)
        let before = try reader().readGrokAuth().accountFingerprint
        try write(#"{"\#(entryKey)":\#(entry(userID: "user-placeholder-2"))}"#)
        XCTAssertNotEqual(try reader().readGrokAuth().accountFingerprint, before)
    }

    func testFingerprintDoesNotCarryTheToken() throws {
        try write(try Fixtures.data("grok_auth"))
        let auth = try reader().readGrokAuth()
        XCTAssertFalse(auth.accountFingerprint.contains("SECRET-MARKER"))
        XCTAssertFalse(auth.accountFingerprint.contains("user-placeholder"))
    }

    func testRefreshTokenIsNeverKept() throws {
        try write(try Fixtures.data("grok_auth"))
        let auth = try reader().readGrokAuth()
        for child in Mirror(reflecting: auth).children {
            XCTAssertFalse("\(child.value)".contains("SECRET-MARKER-REFRESH"), child.label ?? "")
            XCTAssertNotEqual(child.label, "refreshToken")
        }
    }

    func testDescriptionHidesTheToken() throws {
        try write(try Fixtures.data("grok_auth"))
        let auth = try reader().readGrokAuth()
        XCTAssertFalse(String(describing: auth).contains("SECRET-MARKER"))
        XCTAssertFalse(String(reflecting: auth).contains("SECRET-MARKER"))
    }

    func testDefaultURLIsDotGrokInHome() {
        let url = FileGrokAuthReader.defaultURL(environment: [:])
        XCTAssertEqual(url.lastPathComponent, "auth.json")
        XCTAssertEqual(url.deletingLastPathComponent().lastPathComponent, ".grok")
        XCTAssertTrue(url.path.hasPrefix(FileManager.default.homeDirectoryForCurrentUser.path))
    }

    func testDefaultURLHonorsGrokHome() {
        XCTAssertEqual(FileGrokAuthReader.defaultURL(environment: ["GROK_HOME": "/tmp/grok-test"]).path,
                       "/tmp/grok-test/auth.json")
    }
}
