import XCTest
import Foundation
@testable import UsageCore

/// Claude-only behavior. Generic provider guarantees live in ClaudeUsageProviderContractTests.
final class ClaudeUsageProviderTests: XCTestCase {
    private let base = URL(string: "https://api.anthropic.com")!

    private func provider(token: Result<ClaudeToken, Error>,
                          client: UsageHTTPClient) -> ClaudeUsageProvider {
        ClaudeUsageProvider(tokenReader: StubTokenReader(result: token),
                            httpClient: client, baseURL: base)
    }

    func testRequestsOAuthUsagePathWithBetaHeader() async throws {
        let spy = SpyHTTPClient(data: try Fixtures.data("usage_response"), statusCode: 200)
        let token = ClaudeToken(accessToken: "t", expiresAt: Date().addingTimeInterval(3600))
        let snap = try await provider(token: .success(token), client: spy).fetch()
        XCTAssertEqual(snap.status, .ok)
        XCTAssertEqual(snap.limits.count, 3)
        XCTAssertEqual(spy.calls.count, 1)
        XCTAssertEqual(spy.calls[0].url.absoluteString, "https://api.anthropic.com/api/oauth/usage")
        XCTAssertEqual(spy.calls[0].headers["anthropic-beta"], "oauth-2025-04-20")
    }

    func testAccessDeniedReturnsKeychainDenied() async throws {
        let snap = try await provider(token: .failure(TokenReaderError.accessDenied),
                                      client: SpyHTTPClient()).fetch()
        XCTAssertEqual(snap.status, .keychainDenied)
    }

    func testExpiredTokenMessageNamesClaudeCode() async throws {
        let token = ClaudeToken(accessToken: "t", expiresAt: Date().addingTimeInterval(-10))
        let snap = try await provider(token: .success(token), client: SpyHTTPClient()).fetch()
        XCTAssertEqual(snap.status, .stale(reason: "Token expired — open Claude Code to refresh"))
    }

    func test401MessageNamesClaudeCode() async throws {
        let token = ClaudeToken(accessToken: "t", expiresAt: nil)
        let snap = try await provider(token: .success(token), client: SpyHTTPClient(statusCode: 401)).fetch()
        XCTAssertEqual(snap.status, .stale(reason: "Unauthorized — open Claude Code to refresh"))
    }
}
