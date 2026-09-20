import XCTest
import Foundation
@testable import UsageCore

final class ProviderRegistryTests: XCTestCase {
    private func registry() -> ProviderRegistry {
        ProviderRegistry.makeDefault(
            tokenReader: StubTokenReader(result: .failure(TokenReaderError.notFound)),
            codexAuthReader: StubCodexAuthReader(result: .failure(TokenReaderError.notFound)),
            httpClient: SpyHTTPClient(),
            claudeBaseURL: URL(string: "https://api.anthropic.com")!,
            openAIBaseURL: URL(string: "https://chatgpt.com")!)
    }

    func testDefaultRegistryMatchesDisplayOrder() {
        XCTAssertEqual(registry().providers.map(\.id), ProviderID.displayOrder)
    }

    func testNoDuplicateProviders() {
        let ids = registry().providers.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testEachProviderIsWiredToItsOwnCredentialReader() async throws {
        for provider in registry().providers {
            let snap = try await provider.fetch()
            XCTAssertEqual(snap.provider, provider.id)
            XCTAssertEqual(snap.status, .needsSignIn, "\(provider.id)")
        }
    }

    func testClaudeLocalReaderIsWiredToTheClaudeProvider() async throws {
        let local = ClaudeLocalUsage(fiveHour: .init(usedPercentage: 20, resetsAt: nil),
                                     sevenDay: nil, updatedAt: Date())
        let registry = ProviderRegistry.makeDefault(
            tokenReader: StubTokenReader(result: .failure(TokenReaderError.notFound)),
            codexAuthReader: StubCodexAuthReader(result: .failure(TokenReaderError.notFound)),
            httpClient: SpyHTTPClient(),
            claudeBaseURL: URL(string: "https://api.anthropic.com")!,
            openAIBaseURL: URL(string: "https://chatgpt.com")!,
            claudeLocalReader: StubClaudeLocalUsageReader(result: local))
        let claude = registry.providers.first { $0.id == .claude }!
        let snap = try await claude.fetch()
        XCTAssertEqual(snap.status, .ok)
        XCTAssertEqual(snap.limits.map(\.id), ["session"])
    }
}
