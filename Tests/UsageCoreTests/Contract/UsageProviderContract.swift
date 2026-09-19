import XCTest
import Foundation
@testable import UsageCore

enum CredentialOutcome: CaseIterable {
    case valid, expired, notFound, accessDenied, malformed
}

struct ProviderContractSubject {
    let expectedID: ProviderID
    let validFixture: String
    let expectedLimitCount: Int
    let make: (_ credential: CredentialOutcome, _ client: UsageHTTPClient) -> any UsageProvider
}

/// Guarantees every UsageProvider must honor; each check is called from a per-provider test class.
enum UsageProviderContract {
    static let token = "contract-token"
    static let warning = 80.0
    static let critical = 95.0

    private static func fixture(_ s: ProviderContractSubject) throws -> Data {
        try Fixtures.data(s.validFixture)
    }

    /// C1: fetch() never throws — every failure becomes a FetchStatus.
    static func c1NeverThrows(_ s: ProviderContractSubject,
                              file: StaticString = #filePath, line: UInt = #line) async {
        let clients: [UsageHTTPClient] = [
            SpyHTTPClient(data: (try? fixture(s)) ?? Data(), statusCode: 200),
            SpyHTTPClient(statusCode: 401), SpyHTTPClient(statusCode: 429),
            SpyHTTPClient(statusCode: 500), SpyHTTPClient(data: "{".data(using: .utf8)!, statusCode: 200),
            ThrowingHTTPClient(error: URLError(.notConnectedToInternet)),
            ThrowingHTTPClient(error: StubError())
        ]
        for outcome in CredentialOutcome.allCases {
            for client in clients {
                do { _ = try await s.make(outcome, client).fetch() }
                catch { XCTFail("threw for \(outcome) / \(type(of: client)): \(error)", file: file, line: line) }
            }
        }
    }

    /// C2: snapshot.provider == provider.id.
    static func c2ProviderIDMatches(_ s: ProviderContractSubject,
                                    file: StaticString = #filePath, line: UInt = #line) async throws {
        let p = s.make(.valid, SpyHTTPClient(data: try fixture(s), statusCode: 200))
        XCTAssertEqual(p.id, s.expectedID, file: file, line: line)
        let snap = try await p.fetch()
        XCTAssertEqual(snap.provider, s.expectedID, file: file, line: line)
    }

    /// C3: any non-.ok status ⇒ no limits.
    static func c3NonOkHasNoLimits(_ s: ProviderContractSubject,
                                   file: StaticString = #filePath, line: UInt = #line) async throws {
        let cases: [(CredentialOutcome, UsageHTTPClient)] = [
            (.notFound, SpyHTTPClient()), (.expired, SpyHTTPClient()),
            (.accessDenied, SpyHTTPClient()), (.malformed, SpyHTTPClient()),
            (.valid, SpyHTTPClient(statusCode: 401)), (.valid, SpyHTTPClient(statusCode: 500)),
            (.valid, ThrowingHTTPClient(error: URLError(.timedOut))),
            (.valid, SpyHTTPClient(data: "{".data(using: .utf8)!, statusCode: 200))
        ]
        for (outcome, client) in cases {
            let snap = try await s.make(outcome, client).fetch()
            XCTAssertNotEqual(snap.status, .ok, "\(outcome)", file: file, line: line)
            XCTAssertTrue(snap.limits.isEmpty, "\(outcome) \(type(of: client))", file: file, line: line)
        }
    }

    /// C4: valid fixture ⇒ expected limit count and severities derived from thresholds.
    static func c4OkMapsFixture(_ s: ProviderContractSubject,
                                file: StaticString = #filePath, line: UInt = #line) async throws {
        let snap = try await s.make(.valid, SpyHTTPClient(data: try fixture(s), statusCode: 200)).fetch()
        XCTAssertEqual(snap.status, .ok, file: file, line: line)
        XCTAssertEqual(snap.limits.count, s.expectedLimitCount, file: file, line: line)
        for limit in snap.limits {
            XCTAssertEqual(limit.severity,
                           Severity.from(percent: limit.percentUsed, warning: warning, critical: critical),
                           limit.id, file: file, line: line)
            XCTAssertFalse(limit.id.isEmpty, file: file, line: line)
            XCTAssertFalse(limit.label.isEmpty, file: file, line: line)
        }
    }

    /// C5: credential not found ⇒ .needsSignIn.
    static func c5NotFoundNeedsSignIn(_ s: ProviderContractSubject,
                                      file: StaticString = #filePath, line: UInt = #line) async throws {
        let snap = try await s.make(.notFound, SpyHTTPClient()).fetch()
        XCTAssertEqual(snap.status, .needsSignIn, file: file, line: line)
    }

    /// C6: expired credential ⇒ .stale and zero HTTP calls.
    static func c6ExpiredIsStaleWithoutNetwork(_ s: ProviderContractSubject,
                                               file: StaticString = #filePath, line: UInt = #line) async throws {
        let spy = SpyHTTPClient()
        let snap = try await s.make(.expired, spy).fetch()
        guard case .stale = snap.status else {
            return XCTFail("expected .stale, got \(snap.status)", file: file, line: line)
        }
        XCTAssertTrue(spy.calls.isEmpty, file: file, line: line)
    }

    /// C7: HTTP outcome → status class.
    static func c7HTTPStatusMapping(_ s: ProviderContractSubject,
                                    file: StaticString = #filePath, line: UInt = #line) async throws {
        func isStale(_ st: FetchStatus) -> Bool { if case .stale = st { return true }; return false }
        func isError(_ st: FetchStatus) -> Bool { if case .error = st { return true }; return false }

        let status401 = try await s.make(.valid, SpyHTTPClient(statusCode: 401)).fetch().status
        XCTAssertTrue(isStale(status401), "401", file: file, line: line)
        let status429 = try await s.make(.valid, SpyHTTPClient(statusCode: 429)).fetch().status
        XCTAssertTrue(isStale(status429), "429", file: file, line: line)
        let status500 = try await s.make(.valid, SpyHTTPClient(statusCode: 500)).fetch().status
        XCTAssertTrue(isError(status500), "500", file: file, line: line)
        let statusURLError = try await s.make(.valid, ThrowingHTTPClient(error: URLError(.notConnectedToInternet))).fetch().status
        XCTAssertTrue(isStale(statusURLError), "URLError", file: file, line: line)
        let statusBadJSON = try await s.make(.valid, SpyHTTPClient(data: "{".data(using: .utf8)!, statusCode: 200)).fetch().status
        XCTAssertTrue(isError(statusBadJSON), "bad JSON", file: file, line: line)
    }

    /// C8: exactly one GET carrying the bearer token.
    static func c8SendsBearerOnce(_ s: ProviderContractSubject,
                                  file: StaticString = #filePath, line: UInt = #line) async throws {
        let spy = SpyHTTPClient(data: try fixture(s), statusCode: 200)
        _ = try await s.make(.valid, spy).fetch()
        XCTAssertEqual(spy.calls.count, 1, file: file, line: line)
        XCTAssertEqual(spy.calls.first?.headers["Authorization"], "Bearer \(token)", file: file, line: line)
    }

    /// C9: fetchedAt is "now".
    static func c9FetchedAtIsNow(_ s: ProviderContractSubject,
                                 file: StaticString = #filePath, line: UInt = #line) async throws {
        let before = Date()
        let snap = try await s.make(.valid, SpyHTTPClient(data: try fixture(s), statusCode: 200)).fetch()
        let after = Date()
        XCTAssertGreaterThanOrEqual(snap.fetchedAt, before, file: file, line: line)
        XCTAssertLessThanOrEqual(snap.fetchedAt, after, file: file, line: line)
    }
}
