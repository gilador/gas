import XCTest
import Foundation
@testable import UsageCore

final class OpenAIUsageProviderContractTests: XCTestCase {
    private let subject = ProviderContractSubject(
        expectedID: .openai, validFixture: "openai_usage_response", expectedLimitCount: 2
    ) { outcome, client in
        let token = UsageProviderContract.token
        let result: Result<CodexAuth, Error>
        switch outcome {
        case .valid: result = .success(CodexAuth(accessToken: token, accountID: "acct", expiresAt: Date().addingTimeInterval(3600)))
        case .expired: result = .success(CodexAuth(accessToken: token, accountID: "acct", expiresAt: Date().addingTimeInterval(-10)))
        case .notFound: result = .failure(TokenReaderError.notFound)
        case .accessDenied: result = .failure(TokenReaderError.accessDenied)
        case .malformed: result = .failure(TokenReaderError.malformed)
        }
        return OpenAIUsageProvider(authReader: StubCodexAuthReader(result: result), httpClient: client,
                                   baseURL: URL(string: "https://chatgpt.com")!,
                                   warningThreshold: UsageProviderContract.warning,
                                   criticalThreshold: UsageProviderContract.critical)
    }

    func testC1NeverThrows() async { await UsageProviderContract.c1NeverThrows(subject) }
    func testC2ProviderIDMatches() async throws { try await UsageProviderContract.c2ProviderIDMatches(subject) }
    func testC3NonOkHasNoLimits() async throws { try await UsageProviderContract.c3NonOkHasNoLimits(subject) }
    func testC4OkMapsFixture() async throws { try await UsageProviderContract.c4OkMapsFixture(subject) }
    func testC5NotFoundNeedsSignIn() async throws { try await UsageProviderContract.c5NotFoundNeedsSignIn(subject) }
    func testC6ExpiredIsStaleWithoutNetwork() async throws { try await UsageProviderContract.c6ExpiredIsStaleWithoutNetwork(subject) }
    func testC7HTTPStatusMapping() async throws { try await UsageProviderContract.c7HTTPStatusMapping(subject) }
    func testC8SendsBearerOnce() async throws { try await UsageProviderContract.c8SendsBearerOnce(subject) }
    func testC9FetchedAtIsNow() async throws { try await UsageProviderContract.c9FetchedAtIsNow(subject) }
}
