import XCTest
@testable import UsageCore

final class RefreshCountdownTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)
    private func text(_ seconds: TimeInterval) -> String {
        RefreshCountdown.text(until: now.addingTimeInterval(seconds), now: now)
    }

    func testZeroOrNegativeIsNow() {
        XCTAssertEqual(text(0), "now")
        XCTAssertEqual(text(-30), "now")
    }

    func testMinutesRoundUp() {
        XCTAssertEqual(text(15 * 60), "in 15 mins")
        XCTAssertEqual(text(14 * 60 + 1), "in 15 mins")
        XCTAssertEqual(text(14 * 60), "in 14 mins")
    }

    func testSingularMinute() {
        XCTAssertEqual(text(34), "in 1 min")
        XCTAssertEqual(text(60), "in 1 min")
    }

    func testHours() {
        XCTAssertEqual(text(3600), "in 1 hr")
        XCTAssertEqual(text(3600 + 5 * 60), "in 1 hr 5 mins")
        XCTAssertEqual(text(2 * 3600), "in 2 hrs")
        XCTAssertEqual(text(2 * 3600 + 60), "in 2 hrs 1 min")
    }

    func testRoundingCarriesIntoHour() {
        XCTAssertEqual(text(59 * 60 + 30), "in 1 hr")
    }
}
