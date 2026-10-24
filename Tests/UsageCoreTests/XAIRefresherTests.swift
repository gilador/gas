import XCTest
import Foundation
@testable import UsageCore

final class XAIRefresherTests: XCTestCase {
    private let entryKey = "https://auth.x.ai::b1a00492-073a-47ea-816f-4c329264a828"
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func signIn(key: String, userID: String) throws {
        let expiry = ISO8601DateFormatter().string(from: Date().addingTimeInterval(6 * 3600))
        let url = dir.appendingPathComponent("auth.json")
        try Data(#"{"\#(entryKey)":{"key":"\#(key)","expires_at":"\#(expiry)","user_id":"\#(userID)","refresh_token":"SECRET-MARKER-REFRESH"}}"#.utf8)
            .write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func provider(_ client: UsageHTTPClient) -> XAIUsageProvider {
        XAIUsageProvider(authReader: FileGrokAuthReader(fileURL: dir.appendingPathComponent("auth.json"), retryDelay: 0),
                         httpClient: client, versionURL: dir.appendingPathComponent("version.json"))
    }

    func testATokenRefreshDoesNotEndARateLimitWait() async throws {
        try signIn(key: "SECRET-MARKER-1", userID: "user-placeholder-1")
        let spy = SpyHTTPClient(statusCode: 429, responseHeaders: ["Retry-After": "3600"])
        let xai = provider(spy)
        let start = Date()
        let limited = await UsageRefresher.refresh(UsageBoard(), providers: [xai], now: start)
        guard case .rateLimited? = limited.snapshot(for: .xai)?.status else { return XCTFail("expected .rateLimited") }

        try signIn(key: "SECRET-MARKER-2", userID: "user-placeholder-1")
        _ = await UsageRefresher.refresh(limited, providers: [xai], now: start.addingTimeInterval(600))
        _ = await UsageRefresher.refresh(limited, providers: [xai], now: start.addingTimeInterval(600), manual: true)
        XCTAssertEqual(spy.calls.count, 1)
    }

    func testAnotherAccountEndsARateLimitWait() async throws {
        try signIn(key: "SECRET-MARKER-1", userID: "user-placeholder-1")
        let spy = SpyHTTPClient(statusCode: 429, responseHeaders: ["Retry-After": "3600"])
        let xai = provider(spy)
        let start = Date()
        let limited = await UsageRefresher.refresh(UsageBoard(), providers: [xai], now: start)

        try signIn(key: "SECRET-MARKER-2", userID: "user-placeholder-2")
        _ = await UsageRefresher.refresh(limited, providers: [xai], now: start.addingTimeInterval(600))
        XCTAssertEqual(spy.calls.count, 2)
        XCTAssertEqual(spy.calls.last?.headers["Authorization"], "Bearer SECRET-MARKER-2")
    }

    func testARejectedTokenKeepsTheLastValuesAndHoldsTheInterval() async throws {
        try signIn(key: "SECRET-MARKER-1", userID: "user-placeholder-1")
        let client = SequenceHTTPClient(statuses: [200, 401], data: try Fixtures.data("xai_billing_response"))
        let xai = provider(client)
        let start = Date()

        let good = await UsageRefresher.refresh(UsageBoard(), providers: [xai], now: start)
        XCTAssertEqual(good.snapshot(for: .xai)?.status, .ok)
        let goodLimits = good.snapshot(for: .xai)?.limits
        XCTAssertEqual(goodLimits?.map(\.percentUsed), [42.5])

        let rejectedAt = start.addingTimeInterval(300)
        let rejected = await UsageRefresher.refresh(good, providers: [xai], now: rejectedAt)
        XCTAssertEqual(rejected.snapshot(for: .xai)?.status, .stale(reason: "Open Grok CLI to renew its sign-in"))
        XCTAssertEqual(rejected.snapshot(for: .xai)?.limits, goodLimits)
        XCTAssertEqual(rejected.snapshot(for: .xai)?.fetchedAt, good.snapshot(for: .xai)?.fetchedAt)
        XCTAssertEqual(rejected.lastRequest(for: .xai), rejectedAt)

        _ = await UsageRefresher.refresh(rejected, providers: [xai], now: rejectedAt.addingTimeInterval(120))
        _ = await UsageRefresher.refresh(rejected, providers: [xai], now: rejectedAt.addingTimeInterval(120), manual: true)
        XCTAssertEqual(client.authorizations.count, 2)
    }

    func testAnExpiredTokenKeepsTheLastValuesWithoutARequest() async throws {
        let previous = UsageBoard(snapshots: [UsageSnapshot(
            provider: .xai, fetchedAt: Date(timeIntervalSince1970: 100),
            limits: [UsageLimit(id: "weekly_all", label: "Weekly", percentUsed: 30, resetsAt: nil, severity: .normal)],
            status: .ok)])
        let spy = SpyHTTPClient()
        let expired = XAIUsageProvider(
            authReader: StubGrokAuthReader(result: .success(GrokAuth(accessToken: "SECRET-MARKER-1",
                                                                     expiresAt: Date().addingTimeInterval(-60),
                                                                     accountFingerprint: "acct"))),
            httpClient: spy, versionURL: dir.appendingPathComponent("version.json"))
        let board = await UsageRefresher.refresh(previous, providers: [expired])
        XCTAssertEqual(board.snapshot(for: .xai)?.status, .stale(reason: "Open Grok CLI to renew its sign-in"))
        XCTAssertEqual(board.snapshot(for: .xai)?.limits.map(\.percentUsed), [30])
        XCTAssertTrue(spy.calls.isEmpty)
    }
}
