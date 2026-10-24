import XCTest
import Foundation
@testable import UsageCore

final class XAIUsageLogTests: XCTestCase {
    private let markers = ["SECRET-MARKER-1", "SECRET-MARKER-2", "SECRET-MARKER-3", "SECRET-MARKER-4",
                           "SECRET-MARKER-5", "SECRET-MARKER-6", "SECRET-MARKER-7"]

    private var hostileBody: Data {
        Data(#"{"error":{"type":"SECRET-MARKER-2","message":"token SECRET-MARKER-3 rejected","code":"SECRET-MARKER-4"},"config":{"note":"SECRET-MARKER-5"}}"#.utf8)
    }

    private var hostileHeaders: [String: String] {
        ["Retry-After": "SECRET-MARKER-6", "WWW-Authenticate": "Bearer error=\"SECRET-MARKER-7\"",
         "X-Echo": "Bearer SECRET-MARKER-1"]
    }

    func testNothingTheServerSendsReachesTheLogOrDiagnostics() async throws {
        var board = UsageBoard()
        for status in [200, 400, 401, 403, 429, 500] {
            let xai = XAIUsageProvider(
                authReader: StubGrokAuthReader(result: .success(GrokAuth(accessToken: "SECRET-MARKER-1",
                                                                         expiresAt: Date().addingTimeInterval(3600),
                                                                         accountFingerprint: "acct"))),
                httpClient: SpyHTTPClient(data: hostileBody, statusCode: status, responseHeaders: hostileHeaders),
                versionURL: URL(fileURLWithPath: "/nonexistent/version.json"))
            let snapshot = try await xai.fetch().snapshot
            board.replace(snapshot)
            XCTAssertTrue(UsageLog.recentLines().last?.contains("xai HTTP \(status) ") == true, "\(status)")
        }
        let log = UsageLog.recentLines().joined(separator: "\n")
        let report = DiagnosticsReport.render(appVersion: "1", osVersion: "1", now: Date(), keychainEntries: [],
                                              tokenStatus: "ok · no expiry", board: board,
                                              recentLog: UsageLog.recentLines())
        for marker in markers {
            XCTAssertFalse(log.contains(marker), "log leaked \(marker)")
            XCTAssertFalse(report.contains(marker), "report leaked \(marker)")
        }
    }

    func testNetworkErrorLogsOnlyTheCode() async throws {
        let xai = XAIUsageProvider(
            authReader: StubGrokAuthReader(result: .success(GrokAuth(accessToken: "SECRET-MARKER-1",
                                                                     expiresAt: Date().addingTimeInterval(3600),
                                                                     accountFingerprint: "acct"))),
            httpClient: ThrowingHTTPClient(error: URLError(.timedOut, userInfo: [NSLocalizedDescriptionKey: "SECRET-MARKER-2"])),
            versionURL: URL(fileURLWithPath: "/nonexistent/version.json"))
        _ = try await xai.fetch()
        XCTAssertEqual(UsageLog.recentLines().last?.hasSuffix(" xai network error \(URLError.timedOut.rawValue)"), true)
        XCTAssertFalse(UsageLog.recentLines().joined().contains("SECRET-MARKER"))
    }
}
