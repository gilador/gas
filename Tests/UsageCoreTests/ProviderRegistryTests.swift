import XCTest
import Foundation
@testable import UsageCore

final class ProviderRegistryTests: XCTestCase {
    func testDefaultRegistryHoldsClaudeOnly() {
        let registry = ProviderRegistry.makeDefault(
            tokenReader: StubTokenReader(result: .failure(TokenReaderError.notFound)),
            httpClient: StubHTTPClient(data: Data(), statusCode: 200),
            baseURL: URL(string: "https://api.anthropic.com")!)
        XCTAssertEqual(registry.providers.count, 1)
        XCTAssertEqual(registry.providers.first?.id, .claude)
    }
}
