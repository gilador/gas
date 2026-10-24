import XCTest
@testable import UsageCore

final class RetryAfterTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-10-21T07:23:00Z")!

    private func response(_ headers: [String: String]) -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 429,
                        httpVersion: nil, headerFields: headers)!
    }

    private func seconds(_ value: String?) -> TimeInterval {
        RetryAfter.seconds(from: response(value.map { ["Retry-After": $0] } ?? [:]), now: now)
    }

    func testParsesIntegerSeconds() {
        XCTAssertEqual(seconds("850"), 850)
    }
    func testTrimsWhitespace() {
        XCTAssertEqual(seconds(" 12 "), 12)
    }
    func testZeroYieldsZero() {
        XCTAssertEqual(seconds("0"), 0)
    }
    func testMissingHeaderYieldsZero() {
        XCTAssertEqual(seconds(nil), 0)
    }
    func testHTTPDateIsRelativeToNow() {
        XCTAssertEqual(seconds("Wed, 21 Oct 2026 07:28:00 GMT"), 300)
    }
    func testPastHTTPDateYieldsZero() {
        XCTAssertEqual(seconds("Tue, 20 Oct 2026 07:28:00 GMT"), 0)
    }
    func testNegativeYieldsZero() {
        XCTAssertEqual(seconds("-5"), 0)
    }
    func testGarbageYieldsZero() {
        for value in ["soon", "1e3", "inf", "nan", "12.5", "+60", ""] {
            XCTAssertEqual(seconds(value), 0, value)
        }
    }
    func testLogValue() {
        XCTAssertEqual(RetryAfter.logValue("120"), "120")
        XCTAssertEqual(RetryAfter.logValue("Wed, 21 Oct 2026 07:28:00 GMT"), "date")
        XCTAssertEqual(RetryAfter.logValue("soon"), "-")
        XCTAssertEqual(RetryAfter.logValue(nil), "-")
    }
}
