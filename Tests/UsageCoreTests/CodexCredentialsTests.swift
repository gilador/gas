import XCTest
import Foundation
@testable import UsageCore

final class CodexCredentialsTests: XCTestCase {
    private func b64url(_ s: String) -> String {
        Data(s.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    private func jwt(payload: String) -> String {
        "\(b64url("{\"alg\":\"none\"}")).\(b64url(payload)).sig"
    }

    func testParseFixtureReturnsTokenAndAccountID() throws {
        let auth = try CodexCredentials.parse(Fixtures.data("codex_auth"))
        XCTAssertEqual(auth.accessToken, "fake.access.token")
        XCTAssertEqual(auth.accountID, "00000000-0000-4000-8000-000000000000")
        XCTAssertNil(auth.expiresAt)
    }

    func testTokensNullThrowsNotFound() {
        let json = #"{"auth_mode":"apikey","OPENAI_API_KEY":"sk-x","tokens":null}"#.data(using: .utf8)!
        XCTAssertThrowsError(try CodexCredentials.parse(json)) {
            XCTAssertEqual($0 as? TokenReaderError, .notFound)
        }
    }

    func testEmptyAccessTokenThrowsNotFound() {
        let json = #"{"tokens":{"access_token":"","account_id":"a"}}"#.data(using: .utf8)!
        XCTAssertThrowsError(try CodexCredentials.parse(json)) {
            XCTAssertEqual($0 as? TokenReaderError, .notFound)
        }
    }

    func testBadJSONThrowsMalformed() {
        XCTAssertThrowsError(try CodexCredentials.parse("nope".data(using: .utf8)!)) {
            XCTAssertEqual($0 as? TokenReaderError, .malformed)
        }
    }

    func testMissingAccountIDIsNil() throws {
        let json = #"{"tokens":{"access_token":"t"}}"#.data(using: .utf8)!
        XCTAssertNil(try CodexCredentials.parse(json).accountID)
    }

    func testExpiryFromJWTExpClaim() throws {
        let token = jwt(payload: #"{"exp":1790477571,"sub":"x"}"#)
        let json = #"{"tokens":{"access_token":"\#(token)"}}"#.data(using: .utf8)!
        XCTAssertEqual(try CodexCredentials.parse(json).expiresAt,
                       Date(timeIntervalSince1970: 1_790_477_571))
    }

    func testJWTWithoutExpGivesNilExpiry() {
        XCTAssertNil(JWTClaims.expiry(of: jwt(payload: #"{"sub":"x"}"#)))
    }

    func testNonJWTGivesNilExpiry() {
        XCTAssertNil(JWTClaims.expiry(of: "not-a-jwt"))
        XCTAssertNil(JWTClaims.expiry(of: "a.b"))
    }

    func testJWTPayloadNeedingPaddingDecodes() {
        // payload length chosen so base64url output needs stripped "==" padding restored
        let token = jwt(payload: #"{"exp":12}"#)
        XCTAssertEqual(JWTClaims.expiry(of: token), Date(timeIntervalSince1970: 12))
    }
}
