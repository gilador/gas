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

    func testCredentialFingerprintChangesWithTheTokenAndHidesIt() {
        let a = provider(token: .success(ClaudeToken(accessToken: "token-a", expiresAt: nil)),
                         client: SpyHTTPClient()).credentialFingerprint()
        let b = provider(token: .success(ClaudeToken(accessToken: "token-b", expiresAt: nil)),
                         client: SpyHTTPClient()).credentialFingerprint()
        XCTAssertNotNil(a)
        XCTAssertNotEqual(a, b)
        XCTAssertFalse(a?.contains("token-a") ?? true)
    }

    func testCredentialFingerprintIsNilWithoutAToken() {
        XCTAssertNil(provider(token: .failure(TokenReaderError.notFound), client: SpyHTTPClient()).credentialFingerprint())
    }

    private let expired = ClaudeToken(accessToken: "old", expiresAt: Date().addingTimeInterval(-60))
    private let fresh = ClaudeToken(accessToken: "fresh", expiresAt: Date().addingTimeInterval(8 * 3600))

    func testExpiredTokenIsRenewedThenFetched() async throws {
        let renewer = StubRenewer(result: .renewed)
        let spy = SpyHTTPClient(data: try Fixtures.data("usage_response"), statusCode: 200)
        let claude = ClaudeUsageProvider(tokenReader: SequenceTokenReader([.success(expired), .success(fresh)]),
                                         httpClient: spy, baseURL: base, renewer: renewer)
        let snap = try await claude.fetch()
        XCTAssertEqual(snap.status, .ok)
        XCTAssertEqual(renewer.calls, 1)
        XCTAssertEqual(spy.calls.map { $0.headers["Authorization"] }, ["Bearer fresh"])
    }

    func testFailedRenewalAsksToLogIn() async throws {
        let spy = SpyHTTPClient()
        let claude = ClaudeUsageProvider(tokenReader: SequenceTokenReader([.success(expired)]),
                                         httpClient: spy, baseURL: base, renewer: StubRenewer(result: .failed))
        let snap = try await claude.fetch()
        XCTAssertEqual(snap.status, .needsSignIn)
        XCTAssertTrue(spy.calls.isEmpty)
    }

    func testUnavailableRenewalAsksToOpenClaudeCode() async throws {
        let spy = SpyHTTPClient()
        let claude = ClaudeUsageProvider(tokenReader: SequenceTokenReader([.success(expired)]),
                                         httpClient: spy, baseURL: base, renewer: StubRenewer(result: .unavailable))
        let snap = try await claude.fetch()
        XCTAssertEqual(snap.status, .stale(reason: "Couldn't renew — open Claude Code"))
        XCTAssertTrue(spy.calls.isEmpty)
    }

    func testRenewalThatLeavesTheTokenExpiredIsAFailure() async throws {
        let spy = SpyHTTPClient()
        let claude = ClaudeUsageProvider(tokenReader: SequenceTokenReader([.success(expired)]),
                                         httpClient: spy, baseURL: base, renewer: StubRenewer(result: .renewed))
        let snap = try await claude.fetch()
        XCTAssertEqual(snap.status, .stale(reason: "Couldn't renew — open Claude Code"))
        XCTAssertTrue(spy.calls.isEmpty)
    }

    func testDisabledRenewerKeepsTheExpiredMessage() async throws {
        let renewer = StubRenewer(isEnabled: false, result: .renewed)
        let claude = ClaudeUsageProvider(tokenReader: SequenceTokenReader([.success(expired)]),
                                         httpClient: SpyHTTPClient(), baseURL: base, renewer: renewer)
        let snap = try await claude.fetch()
        XCTAssertEqual(snap.status, .stale(reason: "Token expired — open Claude Code to refresh"))
        XCTAssertEqual(renewer.calls, 0)
    }

    private let stale = ClaudeToken(accessToken: "stale", expiresAt: nil)
    private let relogged = ClaudeToken(accessToken: "relogged", expiresAt: nil)

    func test429WithAFailedRenewalAsksToLogIn() async throws {
        let http = SequenceHTTPClient(statuses: [429])
        let renewer = StubRenewer(result: .failed)
        let claude = ClaudeUsageProvider(tokenReader: SequenceTokenReader([.success(stale)]),
                                         httpClient: http, baseURL: base, renewer: renewer)
        let snap = try await claude.fetch()
        XCTAssertEqual(snap.status, .needsSignIn)
        XCTAssertEqual(renewer.calls, 1)
    }

    func testALoggedOutTokenIsNotSentAgainUntilItChanges() async throws {
        let http = SequenceHTTPClient(statuses: [429])
        let claude = ClaudeUsageProvider(tokenReader: SequenceTokenReader([.success(stale), .success(stale), .success(relogged)]),
                                         httpClient: http, baseURL: base, renewer: StubRenewer(result: .failed))
        _ = try await claude.fetch()
        let again = try await claude.fetch()
        XCTAssertEqual(again.status, .needsSignIn)
        XCTAssertEqual(http.authorizations, ["Bearer stale"])
        _ = try await claude.fetch()
        XCTAssertEqual(http.authorizations, ["Bearer stale", "Bearer relogged"])
    }

    func test429RetriesOnceWithARenewedToken() async throws {
        let http = SequenceHTTPClient(statuses: [429, 200], data: try Fixtures.data("usage_response"))
        let claude = ClaudeUsageProvider(tokenReader: SequenceTokenReader([.success(stale), .success(relogged)]),
                                         httpClient: http, baseURL: base, renewer: StubRenewer(result: .renewed))
        let snap = try await claude.fetch()
        XCTAssertEqual(snap.status, .ok)
        XCTAssertEqual(http.authorizations, ["Bearer stale", "Bearer relogged"])
    }

    func test429WithTheSameTokenAfterRenewalIsARealRateLimit() async throws {
        let http = SequenceHTTPClient(statuses: [429])
        let renewer = StubRenewer(result: .renewed)
        let claude = ClaudeUsageProvider(tokenReader: SequenceTokenReader([.success(stale)]),
                                         httpClient: http, baseURL: base, renewer: renewer)
        let snap = try await claude.fetch()
        guard case .rateLimited = snap.status else { return XCTFail("expected .rateLimited, got \(snap.status)") }
        XCTAssertEqual(http.authorizations, ["Bearer stale"])
        XCTAssertEqual(renewer.calls, 1)
    }

    func test429WithTheRenewerOffStaysRateLimited() async throws {
        let renewer = StubRenewer(isEnabled: false, result: .failed)
        let claude = ClaudeUsageProvider(tokenReader: SequenceTokenReader([.success(stale)]),
                                         httpClient: SequenceHTTPClient(statuses: [429]), baseURL: base, renewer: renewer)
        let snap = try await claude.fetch()
        guard case .rateLimited = snap.status else { return XCTFail("expected .rateLimited, got \(snap.status)") }
        XCTAssertEqual(renewer.calls, 0)
    }
}
