import XCTest
import Foundation
@testable import UsageCore

final class ClaudeUsageProviderContractTests: XCTestCase {
    private let subject = ProviderContractSubject(
        expectedID: .claude, validFixture: "usage_response", expectedLimitCount: 3
    ) { outcome, client in
        let token = UsageProviderContract.token
        let result: Result<ClaudeToken, Error>
        switch outcome {
        case .valid: result = .success(ClaudeToken(accessToken: token, expiresAt: Date().addingTimeInterval(3600)))
        case .expired: result = .success(ClaudeToken(accessToken: token, expiresAt: Date().addingTimeInterval(-10)))
        case .notFound: result = .failure(TokenReaderError.notFound)
        case .accessDenied: result = .failure(TokenReaderError.accessDenied)
        case .malformed: result = .failure(TokenReaderError.malformed)
        }
        return ClaudeUsageProvider(tokenReader: StubTokenReader(result: result), httpClient: client,
                                   baseURL: URL(string: "https://api.anthropic.com")!,
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
    func testC10MinimumIntervalNonNegative() { UsageProviderContract.c10MinimumIntervalNonNegative(subject) }
    func testC11RequestSentMatchesTheNetwork() async throws { try await UsageProviderContract.c11RequestSentMatchesTheNetwork(subject) }
}
