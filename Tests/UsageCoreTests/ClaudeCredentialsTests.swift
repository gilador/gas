import XCTest
import Foundation
@testable import UsageCore

final class ClaudeCredentialsTests: XCTestCase {
    func testParseValidJSON() throws {
        let json = """
        {"claudeAiOauth":{"accessToken":"abc123","expiresAt":1750000000000,
          "refreshToken":"r","subscriptionType":"max"}}
        """.data(using: .utf8)!
        let token = try ClaudeCredentials.parse(json)
        XCTAssertEqual(token.accessToken, "abc123")
        XCTAssertEqual(token.expiresAt, Date(timeIntervalSince1970: 1_750_000_000))
    }

    func testParseMissingExpiryYieldsNilDate() throws {
        let json = """
        {"claudeAiOauth":{"accessToken":"abc123"}}
        """.data(using: .utf8)!
        let token = try ClaudeCredentials.parse(json)
        XCTAssertEqual(token.accessToken, "abc123")
        XCTAssertNil(token.expiresAt)
    }

    func testParseMalformedThrows() {
        let json = "{}".data(using: .utf8)!
        XCTAssertThrowsError(try ClaudeCredentials.parse(json)) {
            XCTAssertEqual($0 as? TokenReaderError, .malformed)
        }
    }
}
