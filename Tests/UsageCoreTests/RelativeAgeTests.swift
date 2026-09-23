import XCTest
@testable import UsageCore

final class RelativeAgeTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)
    private func age(_ seconds: TimeInterval) -> String {
        RelativeAge.compact(from: now.addingTimeInterval(-seconds), now: now)
    }

    func testUnderOneSecondIsNow() {
        XCTAssertEqual(age(0), "now")
        XCTAssertEqual(age(0.5), "now")
    }

    func testFutureIsNow() {
        XCTAssertEqual(age(-5), "now")
    }

    func testSeconds() {
        XCTAssertEqual(age(43), "43s ago")
        XCTAssertEqual(age(59.9), "59s ago")
    }

    func testMinutes() {
        XCTAssertEqual(age(60), "1m ago")
        XCTAssertEqual(age(3599), "59m ago")
    }

    func testHours() {
        XCTAssertEqual(age(3600), "1h ago")
        XCTAssertEqual(age(86_399), "23h ago")
    }

    func testDays() {
        XCTAssertEqual(age(86_400), "1d ago")
        XCTAssertEqual(age(86_400 * 3 + 5), "3d ago")
    }
}
