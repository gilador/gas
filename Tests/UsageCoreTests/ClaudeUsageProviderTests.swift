import XCTest
import Foundation
@testable import UsageCore

final class ClaudeUsageProviderTests: XCTestCase {
    private let base = URL(string: "https://api.anthropic.com")!

    private func provider(token: Result<ClaudeToken, Error>,
                          client: UsageHTTPClient) -> ClaudeUsageProvider {
        ClaudeUsageProvider(tokenReader: StubTokenReader(result: token),
                            httpClient: client, baseURL: base)
    }

    func testOkDecodesAndMaps() async throws {
        let json = try Fixtures.data("usage_response")
        let p = provider(token: .success(ClaudeToken(accessToken: "t",
                                                      expiresAt: Date().addingTimeInterval(3600))),
                         client: StubHTTPClient(data: json, statusCode: 200))
        let snap = try await p.fetch()
        XCTAssertEqual(snap.status, .ok)
        XCTAssertEqual(snap.limits.count, 3)
        XCTAssertEqual(snap.provider, .claude)
    }

    func testExpiredTokenReturnsStale() async throws {
        let p = provider(token: .success(ClaudeToken(accessToken: "t",
                                                      expiresAt: Date().addingTimeInterval(-10))),
                         client: StubHTTPClient(data: Data(), statusCode: 200))
        let snap = try await p.fetch()
        guard case .stale = snap.status else { return XCTFail("expected .stale") }
        XCTAssertTrue(snap.limits.isEmpty)
    }

    func test401ReturnsStale() async throws {
        let p = provider(token: .success(ClaudeToken(accessToken: "t", expiresAt: nil)),
                         client: StubHTTPClient(data: Data(), statusCode: 401))
        let snap = try await p.fetch()
        guard case .stale = snap.status else { return XCTFail("expected .stale") }
    }

    func testNotFoundReturnsNeedsSignIn() async throws {
        let p = provider(token: .failure(TokenReaderError.notFound),
                         client: StubHTTPClient(data: Data(), statusCode: 200))
        let snap = try await p.fetch()
        XCTAssertEqual(snap.status, .needsSignIn)
    }

    func testAccessDeniedReturnsKeychainDenied() async throws {
        let p = provider(token: .failure(TokenReaderError.accessDenied),
                         client: StubHTTPClient(data: Data(), statusCode: 200))
        let snap = try await p.fetch()
        XCTAssertEqual(snap.status, .keychainDenied)
    }

    func testServerErrorReturnsError() async throws {
        let p = provider(token: .success(ClaudeToken(accessToken: "t", expiresAt: nil)),
                         client: StubHTTPClient(data: Data(), statusCode: 500))
        let snap = try await p.fetch()
        guard case .error = snap.status else { return XCTFail("expected .error") }
    }

    func testProviderIDIsClaude() {
        let p = provider(token: .failure(TokenReaderError.notFound),
                         client: StubHTTPClient(data: Data(), statusCode: 200))
        XCTAssertEqual(p.id, .claude)
    }
}
