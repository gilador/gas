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

    func testSendsClaudeCodeUserAgent() async throws {
        let spy = SpyHTTPClient(data: try Fixtures.data("usage_response"), statusCode: 200)
        let token = ClaudeToken(accessToken: "t", expiresAt: nil)
        _ = try await provider(token: .success(token), client: spy).fetch()
        XCTAssertEqual(spy.calls[0].headers["User-Agent"], "claude-code/2.1.281")
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

    func test429WithRetryAfterIsRateLimited() async throws {
        let token = ClaudeToken(accessToken: "t", expiresAt: nil)
        let client = SpyHTTPClient(statusCode: 429, responseHeaders: ["Retry-After": "850"])
        let snap = try await provider(token: .success(token), client: client).fetch()
        guard case .rateLimited(let until, let wait) = snap.status else { return XCTFail("expected .rateLimited, got \(snap.status)") }
        XCTAssertEqual(wait, 850)
        XCTAssertEqual(until.timeIntervalSince(snap.fetchedAt), 850, accuracy: 0.001)
        XCTAssertTrue(snap.limits.isEmpty)
    }

    func test429WithoutRetryAfterHasZeroWait() async throws {
        let token = ClaudeToken(accessToken: "t", expiresAt: nil)
        let snap = try await provider(token: .success(token), client: SpyHTTPClient(statusCode: 429)).fetch()
        guard case .rateLimited(_, let wait) = snap.status else { return XCTFail("expected .rateLimited") }
        XCTAssertEqual(wait, 0)
    }

    func testMinimumIntervalIsJustUnderTheFiveMinuteTick() {
        XCTAssertEqual(provider(token: .failure(TokenReaderError.notFound), client: SpyHTTPClient()).minimumInterval, 270)
    }

    func testManualMinimumIntervalIsOneMinute() {
        XCTAssertEqual(provider(token: .failure(TokenReaderError.notFound), client: SpyHTTPClient()).manualMinimumInterval, 60)
    }
}
