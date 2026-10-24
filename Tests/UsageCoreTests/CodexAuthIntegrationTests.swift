import Foundation
import XCTest
@testable import UsageCore

final class CodexAuthIntegrationTests: XCTestCase {
    func testLiveFetchIsOkOrNeedsSignIn() async throws {
        guard ProcessInfo.processInfo.environment["RUN_CODEX_INTEGRATION_TESTS"] != nil else {
            throw XCTSkip("Set RUN_CODEX_INTEGRATION_TESTS=1 to hit the real Codex auth file + network")
        }
        let provider = OpenAIUsageProvider(authReader: FileCodexAuthReader(),
                                           httpClient: URLSessionHTTPClient(),
                                           baseURL: URL(string: "https://chatgpt.com")!)
        let snap = try await provider.fetch().snapshot
        switch snap.status {
        case .ok, .needsSignIn, .stale, .rateLimited: break
        case .error(let message): XCTFail("unexpected error: \(message)")
        case .keychainDenied: XCTFail("keychainDenied is not a Codex status")
        }
    }
}
