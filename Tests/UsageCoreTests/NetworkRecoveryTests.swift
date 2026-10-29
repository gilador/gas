import Foundation
import XCTest
@testable import UsageCore

final class NetworkRecoveryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 10_000)

    private func provider(_ id: ProviderID, client: any UsageHTTPClient) -> any UsageProvider {
        switch id {
        case .claude:
            return ClaudeUsageProvider(tokenReader: StubTokenReader(result: .success(
                ClaudeToken(accessToken: "synthetic", expiresAt: nil))), httpClient: client,
                baseURL: URL(string: "https://api.anthropic.com")!)
        case .openai:
            return OpenAIUsageProvider(authReader: StubCodexAuthReader(result: .success(
                CodexAuth(accessToken: "synthetic", accountID: "account", expiresAt: nil))), httpClient: client,
                baseURL: URL(string: "https://chatgpt.com")!)
        case .xai:
            return XAIUsageProvider(authReader: StubGrokAuthReader(result: .success(
                GrokAuth(accessToken: "synthetic", expiresAt: .distantFuture, accountFingerprint: "account"))),
                httpClient: client, versionURL: URL(fileURLWithPath: "/nonexistent/gas-test-version.json"))
        }
    }

    private func successClient(_ id: ProviderID) throws -> SpyHTTPClient {
        let fixture: String
        switch id {
        case .claude: fixture = "usage_response"
        case .openai: fixture = "openai_usage_response"
        case .xai: fixture = "xai_billing_response"
        }
        return SpyHTTPClient(data: try Fixtures.data(fixture))
    }

    func testOfflineFailureDoesNotStartACooldownAndCanRetryImmediately() async throws {
        for id in ProviderID.displayOrder {
            let offline = provider(id, client: ThrowingHTTPClient(error: URLError(.notConnectedToInternet)))
            let outcome = try await offline.fetch()
            XCTAssertFalse(outcome.requestSent, id.rawValue)
            XCTAssertEqual(outcome.snapshot.status, .stale(reason: "Network unavailable — retrying"))
            let board = await UsageRefresher.refresh(UsageBoard(), providers: [offline], now: now)
            XCTAssertNil(board.lastRequest(for: id), id.rawValue)
            for manual in [false, true] {
                let client = try successClient(id)
                let recovered = await UsageRefresher.refresh(board, providers: [provider(id, client: client)],
                                                             now: now.addingTimeInterval(1), manual: manual)
                XCTAssertEqual(client.calls.count, 1, id.rawValue)
                XCTAssertEqual(recovered.snapshot(for: id)?.status, .ok)
            }
        }
    }

    func testOfflineFailurePreservesLastGoodValuesAndPreviousRequestTime() async throws {
        for id in ProviderID.displayOrder {
            let good = UsageSnapshot(provider: id, fetchedAt: now.addingTimeInterval(-300), limits: [
                UsageLimit(id: "weekly_all", label: "Weekly", percentUsed: 42, resetsAt: nil, severity: .normal)
            ], status: .ok)
            var previous = UsageBoard(snapshots: [good])
            previous.markRequested(id, at: good.fetchedAt)
            let offline = provider(id, client: ThrowingHTTPClient(error: URLError(.notConnectedToInternet)))
            let board = await UsageRefresher.refresh(previous, providers: [offline], now: now)
            XCTAssertEqual(board.lastRequest(for: id), good.fetchedAt, id.rawValue)
            XCTAssertEqual(board.snapshot(for: id)?.limits, good.limits)
            XCTAssertEqual(board.snapshot(for: id)?.fetchedAt, good.fetchedAt)
        }
    }

    func testAmbiguousNetworkFailuresStillCountTowardCooldowns() async throws {
        for id in ProviderID.displayOrder {
            for code in [URLError.timedOut, .networkConnectionLost, .cannotConnectToHost] {
                let failing = provider(id, client: ThrowingHTTPClient(error: URLError(code)))
                let outcome = try await failing.fetch()
                XCTAssertTrue(outcome.requestSent, id.rawValue)
                let board = await UsageRefresher.refresh(UsageBoard(), providers: [failing], now: now)
                XCTAssertEqual(board.lastRequest(for: id), now, id.rawValue)
                let client = try successClient(id)
                _ = await UsageRefresher.refresh(board, providers: [provider(id, client: client)],
                                                now: now.addingTimeInterval(1), manual: true)
                XCTAssertTrue(client.calls.isEmpty, id.rawValue)
            }
        }
    }

    func testClaudeRateLimitStillCountsWhenRenewedRequestFindsNoNetwork() async throws {
        let reader = SequenceTokenReader([
            .success(ClaudeToken(accessToken: "synthetic-old", expiresAt: nil)),
            .success(ClaudeToken(accessToken: "synthetic-new", expiresAt: nil))
        ])
        let claude = ClaudeUsageProvider(tokenReader: reader, httpClient: RateLimitedThenOfflineClient(),
                                         baseURL: URL(string: "https://api.anthropic.com")!,
                                         renewer: StubRenewer(result: .renewed))
        let outcome = try await claude.fetch()
        XCTAssertTrue(outcome.requestSent)
        guard case .rateLimited(_, let wait) = outcome.snapshot.status else {
            return XCTFail("The response before the disconnect must keep its rate-limit wait")
        }
        XCTAssertEqual(wait, 850)
    }
}

private actor RateLimitedThenOfflineClient: UsageHTTPClient {
    private var calls = 0

    func get(_ url: URL, headers: [String: String]) async throws -> (Data, HTTPURLResponse) {
        calls += 1
        if calls > 1 { throw URLError(.notConnectedToInternet) }
        return (Data(), HTTPURLResponse(url: url, statusCode: 429, httpVersion: nil,
                                       headerFields: ["Retry-After": "850"])!)
    }
}
