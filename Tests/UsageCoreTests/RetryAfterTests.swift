import XCTest
@testable import UsageCore

final class RetryAfterTests: XCTestCase {
    private func response(_ headers: [String: String]) -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 429,
                        httpVersion: nil, headerFields: headers)!
    }

    func testParsesIntegerSeconds() {
        XCTAssertEqual(RetryAfter.seconds(from: response(["Retry-After": "850"])), 850)
    }
    func testTrimsWhitespace() {
        XCTAssertEqual(RetryAfter.seconds(from: response(["Retry-After": " 12 "])), 12)
    }
    func testZeroYieldsZero() {
        XCTAssertEqual(RetryAfter.seconds(from: response(["Retry-After": "0"])), 0)
    }
    func testMissingHeaderYieldsZero() {
        XCTAssertEqual(RetryAfter.seconds(from: response([:])), 0)
    }
    func testHTTPDateYieldsZero() {
        XCTAssertEqual(RetryAfter.seconds(from: response(["Retry-After": "Wed, 21 Oct 2026 07:28:00 GMT"])), 0)
    }
    func testNegativeYieldsZero() {
        XCTAssertEqual(RetryAfter.seconds(from: response(["Retry-After": "-5"])), 0)
    }
}
