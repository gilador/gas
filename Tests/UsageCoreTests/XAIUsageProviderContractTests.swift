import XCTest
import Foundation
@testable import UsageCore

final class XAIUsageProviderContractTests: XCTestCase {
    private let subject = ProviderContractSubject(
        expectedID: .xai, validFixture: "xai_billing_response", expectedLimitCount: 1
    ) { outcome, client in
        let token = UsageProviderContract.token
        let result: Result<GrokAuth, Error>
        switch outcome {
        case .valid: result = .success(GrokAuth(accessToken: token, expiresAt: Date().addingTimeInterval(3600), accountFingerprint: "acct"))
        case .expired: result = .success(GrokAuth(accessToken: token, expiresAt: Date().addingTimeInterval(-10), accountFingerprint: "acct"))
        case .notFound: result = .failure(GrokAuthError.notFound)
        case .accessDenied: result = .failure(GrokAuthError.unreadable)
        case .malformed: result = .failure(GrokAuthError.malformed)
        }
        return XAIUsageProvider(authReader: StubGrokAuthReader(result: result), httpClient: client,
                                versionURL: URL(fileURLWithPath: "/nonexistent/version.json"),
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
