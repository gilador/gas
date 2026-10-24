import XCTest
@testable import UsageCore

final class RateLimitBackoffTests: XCTestCase {
    func testServerValueWins() {
        XCTAssertEqual(RateLimitBackoff.wait(retryAfter: 850, previous: nil), 850)
        XCTAssertEqual(RateLimitBackoff.wait(retryAfter: 850, previous: .rateLimited(until: Date(), wait: 3600)), 850)
    }
    func testServerValueIsHonoredUpToADay() {
        XCTAssertEqual(RateLimitBackoff.wait(retryAfter: 10_000, previous: nil), 10_000)
        XCTAssertEqual(RateLimitBackoff.wait(retryAfter: 99_999, previous: nil), 86_400)
    }
    func testNoHeaderStartsAtFifteenMinutes() {
        XCTAssertEqual(RateLimitBackoff.wait(retryAfter: 0, previous: nil), 900)
        XCTAssertEqual(RateLimitBackoff.wait(retryAfter: 0, previous: .ok), 900)
        XCTAssertEqual(RateLimitBackoff.wait(retryAfter: 0, previous: .stale(reason: "x")), 900)
    }
    func testNoHeaderDoublesOnRepeat() {
        XCTAssertEqual(RateLimitBackoff.wait(retryAfter: 0, previous: .rateLimited(until: Date(), wait: 900)), 1800)
        XCTAssertEqual(RateLimitBackoff.wait(retryAfter: 0, previous: .rateLimited(until: Date(), wait: 1800)), 3600)
    }
    func testDoublingIsCapped() {
        XCTAssertEqual(RateLimitBackoff.wait(retryAfter: 0, previous: .rateLimited(until: Date(), wait: 3600)), 7200)
        XCTAssertEqual(RateLimitBackoff.wait(retryAfter: 0, previous: .rateLimited(until: Date(), wait: 7200)), 7200)
    }
    func testTinyPreviousWaitIsLiftedToMinimumBeforeDoubling() {
        XCTAssertEqual(RateLimitBackoff.wait(retryAfter: 0, previous: .rateLimited(until: Date(), wait: 10)), 1800)
    }
}
