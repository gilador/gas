import XCTest
@testable import UsageCore

final class DiagnosticsReportTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    func testTokenStatusShowsTheExpiryOnly() {
        let token = ClaudeToken(accessToken: "sk-secret", expiresAt: now.addingTimeInterval(3600))
        XCTAssertEqual(DiagnosticsReport.tokenStatus(.success(token), now: now), "ok · expires 1970-01-12T14:46:40Z")
    }

    func testTokenStatusMarksAnExpiredToken() {
        let token = ClaudeToken(accessToken: "sk-secret", expiresAt: now.addingTimeInterval(-60))
        XCTAssertEqual(DiagnosticsReport.tokenStatus(.success(token), now: now), "expired · 1970-01-12T13:45:40Z")
    }

    func testTokenStatusWithoutExpiry() {
        let token = ClaudeToken(accessToken: "sk-secret", expiresAt: nil)
        XCTAssertEqual(DiagnosticsReport.tokenStatus(.success(token), now: now), "ok · no expiry")
    }

    func testTokenStatusForReadFailures() {
        XCTAssertEqual(DiagnosticsReport.tokenStatus(.failure(TokenReaderError.notFound), now: now), "not found")
        XCTAssertEqual(DiagnosticsReport.tokenStatus(.failure(TokenReaderError.accessDenied), now: now), "access denied")
    }

    func testReportListsEverySection() {
        let entries = [KeychainEntrySummary(service: "Claude Code-credentials-2f838907", account: "dana", modified: now)]
        let board = UsageBoard(snapshots: [UsageSnapshot(provider: .claude, fetchedAt: now, limits: [],
                                                         status: .rateLimited(until: now, wait: 1555))])
        let report = DiagnosticsReport.render(appVersion: "1.0.13 (17)", osVersion: "Version 26.0", now: now,
                                              keychainEntries: entries, tokenStatus: "ok · no expiry",
                                              board: board, recentLog: ["claude HTTP 429 retry-after=1555"])
        XCTAssertTrue(report.contains("gas 1.0.13 (17) · macOS Version 26.0 · 1970-01-12T13:46:40Z"))
        XCTAssertTrue(report.contains("Claude Code-credentials-2f838907 · account dana · modified 1970-01-12T13:46:40Z"))
        XCTAssertTrue(report.contains("gas reads: Claude Code-credentials · ok · no expiry"))
        XCTAssertTrue(report.contains("\"rateLimited\""))
        XCTAssertTrue(report.contains("claude HTTP 429 retry-after=1555"))
    }

    func testReportSaysWhenNoEntryExists() {
        let report = DiagnosticsReport.render(appVersion: "1", osVersion: "1", now: now, keychainEntries: [],
                                              tokenStatus: "not found", board: UsageBoard(), recentLog: [])
        XCTAssertTrue(report.contains("no Claude Code entries"))
        XCTAssertTrue(report.contains("no requests since launch"))
    }
}
