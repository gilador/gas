import XCTest
import Foundation
@testable import UsageCore

final class OpenAIUsageProviderTests: XCTestCase {
    private let base = URL(string: "https://chatgpt.com")!

    private func provider(auth: Result<CodexAuth, Error>, client: UsageHTTPClient) -> OpenAIUsageProvider {
        OpenAIUsageProvider(authReader: StubCodexAuthReader(result: auth), httpClient: client, baseURL: base)
    }
    private func validAuth(accountID: String? = "acct-1") -> CodexAuth {
        CodexAuth(accessToken: "tok", accountID: accountID, expiresAt: Date().addingTimeInterval(3600))
    }

    func testRequestsWhamUsagePathWithAccountHeader() async throws {
        let spy = SpyHTTPClient(data: try Fixtures.data("openai_usage_response"), statusCode: 200)
        let snap = try await provider(auth: .success(validAuth()), client: spy).fetch().snapshot
        XCTAssertEqual(snap.status, .ok)
        XCTAssertEqual(snap.limits.map(\.id), ["session", "weekly_all"])
        XCTAssertEqual(spy.calls.count, 1)
        XCTAssertEqual(spy.calls[0].url.absoluteString, "https://chatgpt.com/backend-api/wham/usage")
        XCTAssertEqual(spy.calls[0].headers["Authorization"], "Bearer tok")
        XCTAssertEqual(spy.calls[0].headers["ChatGPT-Account-Id"], "acct-1")
        XCTAssertEqual(spy.calls[0].headers["Accept"], "application/json")
    }

    func testAccountHeaderOmittedWhenUnknown() async throws {
        let spy = SpyHTTPClient(data: try Fixtures.data("openai_usage_response"), statusCode: 200)
        _ = try await provider(auth: .success(validAuth(accountID: nil)), client: spy).fetch().snapshot
        XCTAssertNil(spy.calls[0].headers["ChatGPT-Account-Id"])
    }

    func testAccountHeaderOmittedWhenEmpty() async throws {
        let spy = SpyHTTPClient(data: try Fixtures.data("openai_usage_response"), statusCode: 200)
        _ = try await provider(auth: .success(validAuth(accountID: "")), client: spy).fetch().snapshot
        XCTAssertNil(spy.calls[0].headers["ChatGPT-Account-Id"])
    }

    func testAccessDeniedBecomesError() async throws {
        let snap = try await provider(auth: .failure(TokenReaderError.accessDenied),
                                      client: SpyHTTPClient()).fetch().snapshot
        XCTAssertEqual(snap.status, .error(message: "Can't read Codex credentials"))
    }

    func testMalformedBecomesError() async throws {
        let snap = try await provider(auth: .failure(TokenReaderError.malformed),
                                      client: SpyHTTPClient()).fetch().snapshot
        XCTAssertEqual(snap.status, .error(message: "Can't read Codex credentials"))
    }

    func testExpiredTokenMessageNamesCodex() async throws {
        let auth = CodexAuth(accessToken: "tok", accountID: nil, expiresAt: Date().addingTimeInterval(-1))
        let snap = try await provider(auth: .success(auth), client: SpyHTTPClient()).fetch().snapshot
        XCTAssertEqual(snap.status, .stale(reason: "Token expired — open Codex to refresh"))
    }

    func test401MessageNamesCodex() async throws {
        let snap = try await provider(auth: .success(validAuth()), client: SpyHTTPClient(statusCode: 401)).fetch().snapshot
        XCTAssertEqual(snap.status, .stale(reason: "Unauthorized — open Codex to refresh"))
    }

    func testNullRateLimitGivesOkWithNoLimits() async throws {
        let body = #"{"rate_limit":null}"#.data(using: .utf8)!
        let snap = try await provider(auth: .success(validAuth()), client: SpyHTTPClient(data: body)).fetch().snapshot
        XCTAssertEqual(snap.status, .ok)
        XCTAssertTrue(snap.limits.isEmpty)
    }

    func testProviderIDIsOpenAI() {
        XCTAssertEqual(provider(auth: .failure(TokenReaderError.notFound), client: SpyHTTPClient()).id, .openai)
    }

    func test429WithRetryAfterIsRateLimited() async throws {
        let client = SpyHTTPClient(statusCode: 429, responseHeaders: ["Retry-After": "850"])
        let snap = try await provider(auth: .success(validAuth()), client: client).fetch().snapshot
        guard case .rateLimited(let until, let wait) = snap.status else { return XCTFail("expected .rateLimited, got \(snap.status)") }
        XCTAssertEqual(wait, 850)
        XCTAssertEqual(until.timeIntervalSince(snap.fetchedAt), 850, accuracy: 0.001)
        XCTAssertTrue(snap.limits.isEmpty)
    }

    func test429WithoutRetryAfterHasZeroWait() async throws {
        let snap = try await provider(auth: .success(validAuth()), client: SpyHTTPClient(statusCode: 429)).fetch().snapshot
        guard case .rateLimited(_, let wait) = snap.status else { return XCTFail("expected .rateLimited") }
        XCTAssertEqual(wait, 0)
    }

    func testManualMinimumIntervalIsOneMinute() {
        XCTAssertEqual(provider(auth: .failure(TokenReaderError.notFound), client: SpyHTTPClient()).manualMinimumInterval, 60)
    }

    func testFingerprintIsTheAccountID() async throws {
        let codex = provider(auth: .success(validAuth()), client: SpyHTTPClient(statusCode: 429))
        XCTAssertEqual(codex.credentialFingerprint(), "acct-1")
        let outcome = try await codex.fetch()
        XCTAssertEqual(outcome.credentialFingerprint, "acct-1")
        XCTAssertTrue(outcome.requestSent)
    }

    func testFingerprintIsNilWithoutAnAccountID() async throws {
        let noAccount = provider(auth: .success(validAuth(accountID: nil)), client: SpyHTTPClient(statusCode: 429))
        XCTAssertNil(noAccount.credentialFingerprint())
        let outcome = try await noAccount.fetch()
        XCTAssertNil(outcome.credentialFingerprint)
    }

    func testFingerprintIgnoresATokenRotation() {
        let before = provider(auth: .success(CodexAuth(accessToken: "tok-a", accountID: "acct-1", expiresAt: nil)),
                              client: SpyHTTPClient())
        let after = provider(auth: .success(CodexAuth(accessToken: "tok-b", accountID: "acct-1", expiresAt: nil)),
                             client: SpyHTTPClient())
        XCTAssertEqual(before.credentialFingerprint(), after.credentialFingerprint())
    }

    func testMinimumIntervalDefaultsToJustUnderTheTick() {
        XCTAssertEqual(provider(auth: .success(validAuth()), client: SpyHTTPClient()).minimumInterval, 270)
    }
}
