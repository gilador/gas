import XCTest
import Foundation
@testable import UsageCore

private final class SteppingClock: @unchecked Sendable {
    private let lock = NSLock()
    private var times: [Date]
    init(_ times: [Date]) { self.times = times }
    func now() -> Date {
        lock.lock(); defer { lock.unlock() }
        return times.count > 1 ? times.removeFirst() : times[0]
    }
}

final class XAIUsageProviderTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_767_600_000)
    private let renew = FetchStatus.stale(reason: "Open Grok CLI to renew its sign-in")
    private var versionURL: URL!

    override func setUpWithError() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        versionURL = dir.appendingPathComponent("version.json")
        try writeVersion(#"{"version":"1.0.70","stable_version":"1.0.70","checked_at":"2026-01-05T09:00:00.000000Z"}"#)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: versionURL.deletingLastPathComponent())
    }

    private func writeVersion(_ text: String) throws {
        try Data(text.utf8).write(to: versionURL)
    }

    private func auth(expiresIn seconds: TimeInterval = 3600, account: String = "acct-fingerprint") -> GrokAuth {
        GrokAuth(accessToken: "SECRET-MARKER-1", expiresAt: now.addingTimeInterval(seconds), accountFingerprint: account)
    }

    private func provider(_ result: Result<GrokAuth, Error>, client: UsageHTTPClient,
                          clock: SteppingClock? = nil) -> XAIUsageProvider {
        let clock = clock ?? SteppingClock([now])
        return XAIUsageProvider(authReader: StubGrokAuthReader(result: result), httpClient: client,
                                versionURL: versionURL, now: { clock.now() })
    }

    private func billing() throws -> Data { try Fixtures.data("xai_billing_response") }

    private let noPercent = Data(#"{"config":{"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY"},"onDemandCap":{"val":0}}}"#.utf8)

    func testFetchesTheBillingEndpointWithTheExpectedHeaders() async throws {
        let spy = SpyHTTPClient(data: try billing())
        let outcome = try await provider(.success(auth()), client: spy).fetch()
        XCTAssertEqual(outcome.snapshot.status, .ok)
        XCTAssertEqual(outcome.snapshot.provider, .xai)
        XCTAssertEqual(outcome.snapshot.fetchedAt, now)
        XCTAssertEqual(outcome.snapshot.limits.map(\.id), ["weekly_all"])
        XCTAssertEqual(outcome.snapshot.limits.first?.percentUsed, 42.5)
        XCTAssertTrue(outcome.requestSent)
        XCTAssertEqual(outcome.credentialFingerprint, "acct-fingerprint")
        XCTAssertEqual(spy.calls.count, 1)
        XCTAssertEqual(spy.calls[0].url, GrokHTTPClient.billingURL)
        XCTAssertEqual(spy.calls[0].headers, ["Authorization": "Bearer SECRET-MARKER-1",
                                              "Accept": "application/json",
                                              "x-grok-client-version": "1.0.70"])
    }

    func testVersionHeaderIsLeftOutWhenTheFileIsMissing() async throws {
        try FileManager.default.removeItem(at: versionURL)
        let spy = SpyHTTPClient(data: try billing())
        _ = try await provider(.success(auth()), client: spy).fetch()
        XCTAssertNil(spy.calls[0].headers["x-grok-client-version"])
    }

    func testVersionHeaderIsLeftOutWhenTheVersionIsInvalid() async throws {
        for text in [#"{"version":"1.0.70\r\nX-Injected: 1"}"#, #"{"version":""}"#,
                     #"{"version":"\#(String(repeating: "1", count: 33))"}"#, #"{"version":1}"#, "{", "[]"] {
            try writeVersion(text)
            let spy = SpyHTTPClient(data: try billing())
            _ = try await provider(.success(auth()), client: spy).fetch()
            XCTAssertNil(spy.calls[0].headers["x-grok-client-version"], text)
        }
    }

    func testVersionWithPlusAndDashIsSent() async throws {
        try writeVersion(#"{"version":"1.1.0-beta.2+build-7"}"#)
        let spy = SpyHTTPClient(data: try billing())
        _ = try await provider(.success(auth()), client: spy).fetch()
        XCTAssertEqual(spy.calls[0].headers["x-grok-client-version"], "1.1.0-beta.2+build-7")
    }

    func testMissingSignInNeedsSignInWithoutARequest() async throws {
        let spy = SpyHTTPClient()
        let outcome = try await provider(.failure(GrokAuthError.notFound), client: spy).fetch()
        XCTAssertEqual(outcome.snapshot.status, .needsSignIn)
        XCTAssertFalse(outcome.requestSent)
        XCTAssertTrue(spy.calls.isEmpty)
    }

    func testUnreadableSignInIsAnErrorWithoutARequest() async throws {
        for error in [GrokAuthError.unreadable, .malformed, .ambiguous] {
            let spy = SpyHTTPClient()
            let outcome = try await provider(.failure(error), client: spy).fetch()
            XCTAssertEqual(outcome.snapshot.status, .error(message: "Can't read Grok sign-in"), "\(error)")
            XCTAssertFalse(outcome.requestSent)
            XCTAssertTrue(spy.calls.isEmpty)
        }
    }

    func testExpiredTokenIsStaleWithoutARequest() async throws {
        let spy = SpyHTTPClient(data: try billing())
        let outcome = try await provider(.success(auth(expiresIn: -1)), client: spy).fetch()
        XCTAssertEqual(outcome.snapshot.status, renew)
        XCTAssertFalse(outcome.requestSent)
        XCTAssertTrue(spy.calls.isEmpty)
    }

    func testTokenInsideTheSafetyMarginIsTreatedAsExpired() async throws {
        let spy = SpyHTTPClient(data: try billing())
        let outcome = try await provider(.success(auth(expiresIn: 60)), client: spy).fetch()
        XCTAssertEqual(outcome.snapshot.status, renew)
        XCTAssertTrue(spy.calls.isEmpty)
    }

    func testTokenJustOutsideTheSafetyMarginIsSent() async throws {
        let spy = SpyHTTPClient(data: try billing())
        let outcome = try await provider(.success(auth(expiresIn: 61)), client: spy).fetch()
        XCTAssertEqual(outcome.snapshot.status, .ok)
        XCTAssertEqual(spy.calls.count, 1)
    }

    func testNoPercentBeforeExpiryIsAnError() async throws {
        let outcome = try await provider(.success(auth()), client: SpyHTTPClient(data: noPercent)).fetch()
        XCTAssertEqual(outcome.snapshot.status, .error(message: "Grok returned no usage"))
        XCTAssertTrue(outcome.snapshot.limits.isEmpty)
        XCTAssertTrue(outcome.requestSent)
    }

    func testNoPercentAfterExpiryNeedsRenewal() async throws {
        let clock = SteppingClock([now, now.addingTimeInterval(7200)])
        let outcome = try await provider(.success(auth(expiresIn: 3600)), client: SpyHTTPClient(data: noPercent),
                                         clock: clock).fetch()
        XCTAssertEqual(outcome.snapshot.status, renew)
        XCTAssertTrue(outcome.snapshot.limits.isEmpty)
        XCTAssertTrue(outcome.requestSent)
    }

    func testEmptyConfigIsAnError() async throws {
        let outcome = try await provider(.success(auth()), client: SpyHTTPClient(data: Data("{}".utf8))).fetch()
        XCTAssertEqual(outcome.snapshot.status, .error(message: "Grok returned no usage"))
    }

    func testUnauthorizedNeedsRenewalAndCountsAsARequest() async throws {
        let outcome = try await provider(.success(auth()), client: SpyHTTPClient(statusCode: 401)).fetch()
        XCTAssertEqual(outcome.snapshot.status, renew)
        XCTAssertTrue(outcome.requestSent)
        XCTAssertEqual(outcome.credentialFingerprint, "acct-fingerprint")
    }

    func testForbiddenIsDeniedNotExpired() async throws {
        let outcome = try await provider(.success(auth()), client: SpyHTTPClient(statusCode: 403)).fetch()
        XCTAssertEqual(outcome.snapshot.status, .error(message: "Grok denied access"))
    }

    func testRateLimitedHonorsRetryAfterSeconds() async throws {
        let client = SpyHTTPClient(statusCode: 429, responseHeaders: ["Retry-After": "850"])
        let outcome = try await provider(.success(auth()), client: client).fetch()
        XCTAssertEqual(outcome.snapshot.status, .rateLimited(until: now.addingTimeInterval(850), wait: 850))
        XCTAssertEqual(outcome.credentialFingerprint, "acct-fingerprint")
    }

    func testRateLimitedHonorsRetryAfterDate() async throws {
        let date = now.addingTimeInterval(600)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        let client = SpyHTTPClient(statusCode: 429, responseHeaders: ["Retry-After": formatter.string(from: date)])
        let outcome = try await provider(.success(auth()), client: client).fetch()
        XCTAssertEqual(outcome.snapshot.status, .rateLimited(until: date, wait: 600))
    }

    func testOtherStatusIsAnError() async throws {
        let outcome = try await provider(.success(auth()), client: SpyHTTPClient(statusCode: 500)).fetch()
        XCTAssertEqual(outcome.snapshot.status, .error(message: "HTTP 500"))
    }

    func testBadJSONIsAnError() async throws {
        let outcome = try await provider(.success(auth()), client: SpyHTTPClient(data: Data("{".utf8))).fetch()
        XCTAssertEqual(outcome.snapshot.status, .error(message: "Couldn't read usage data"))
    }

    func testNetworkErrorIsStale() async throws {
        let outcome = try await provider(.success(auth()),
                                         client: ThrowingHTTPClient(error: URLError(.notConnectedToInternet))).fetch()
        XCTAssertEqual(outcome.snapshot.status, .stale(reason: "Network unavailable — retrying"))
        XCTAssertTrue(outcome.requestSent)
    }

    func testOversizedResponseIsAnError() async throws {
        let outcome = try await provider(.success(auth()),
                                         client: ThrowingHTTPClient(error: GrokHTTPClientError.responseTooLarge)).fetch()
        XCTAssertEqual(outcome.snapshot.status, .error(message: "Unexpected error"))
    }

    func testFingerprintIsTheAccount() {
        XCTAssertEqual(provider(.success(auth()), client: SpyHTTPClient()).credentialFingerprint(), "acct-fingerprint")
        XCTAssertNil(provider(.failure(GrokAuthError.notFound), client: SpyHTTPClient()).credentialFingerprint())
    }

    func testIntervalsHoldFiveMinutesForEveryRefresh() {
        let xai = provider(.success(auth()), client: SpyHTTPClient())
        XCTAssertEqual(xai.id, .xai)
        XCTAssertEqual(xai.minimumInterval, 270)
        XCTAssertEqual(xai.manualMinimumInterval, 270)
    }

    func testDefaultVersionURLIsNextToTheSignIn() {
        XCTAssertEqual(XAIUsageProvider.defaultVersionURL(environment: ["GROK_HOME": "/tmp/grok-test"]).path,
                       "/tmp/grok-test/version.json")
    }
}
