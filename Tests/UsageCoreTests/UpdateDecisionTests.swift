import XCTest
@testable import UsageCore

final class UpdateDecisionTests: XCTestCase {
    private func info(_ version: String) -> ReleaseInfo {
        ReleaseInfo(version: AppVersion(version)!,
                    pageURL: URL(string: "https://github.com/gilador/gas/releases/tag/v\(version)")!,
                    pkgURL: URL(string: "https://github.com/gilador/gas/releases/download/v\(version)/gas-\(version).pkg")!,
                    checksumURL: URL(string: "https://github.com/gilador/gas/releases/download/v\(version)/gas-\(version).pkg.sha256")!)
    }

    func testSameOrOlderReleaseIsUpToDate() {
        XCTAssertEqual(UpdateDecision.decide(installed: AppVersion("1.0.24")!, latest: info("1.0.24"), skipped: nil), .upToDate)
        XCTAssertEqual(UpdateDecision.decide(installed: AppVersion("1.0.25")!, latest: info("1.0.24"), skipped: nil), .upToDate)
    }

    func testNewerReleaseIsAvailable() {
        XCTAssertEqual(UpdateDecision.decide(installed: AppVersion("1.0.23")!, latest: info("1.0.24"), skipped: nil),
                       .available(info("1.0.24")))
    }

    func testASkippedVersionStaysHidden() {
        XCTAssertEqual(UpdateDecision.decide(installed: AppVersion("1.0.23")!, latest: info("1.0.24"),
                                             skipped: AppVersion("1.0.24")), .skipped)
    }

    func testANewerReleaseAfterASkipShowsAgain() {
        XCTAssertEqual(UpdateDecision.decide(installed: AppVersion("1.0.23")!, latest: info("1.0.25"),
                                             skipped: AppVersion("1.0.24")), .available(info("1.0.25")))
    }
}
