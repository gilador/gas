import XCTest
@testable import UsageCore

final class OpenAIUsageDTOTests: XCTestCase {
    func testDecodesFixture() throws {
        let r = try JSONDecoder().decode(OpenAIUsageResponse.self,
                                         from: Fixtures.data("openai_usage_response"))
        XCTAssertEqual(r.rateLimit?.primaryWindow?.usedPercent, 32)
        XCTAssertEqual(r.rateLimit?.primaryWindow?.limitWindowSeconds, 18000)
        XCTAssertEqual(r.rateLimit?.primaryWindow?.resetAt, 1_789_726_348)
        XCTAssertEqual(r.rateLimit?.secondaryWindow?.usedPercent, 56)
        XCTAssertEqual(r.rateLimit?.secondaryWindow?.limitWindowSeconds, 604_800)
    }

    func testIntegerPercentDecodesAsDouble() throws {
        let json = #"{"rate_limit":{"primary_window":{"used_percent":7}}}"#.data(using: .utf8)!
        let r = try JSONDecoder().decode(OpenAIUsageResponse.self, from: json)
        XCTAssertEqual(r.rateLimit?.primaryWindow?.usedPercent, 7.0)
        XCTAssertNil(r.rateLimit?.primaryWindow?.limitWindowSeconds)
        XCTAssertNil(r.rateLimit?.secondaryWindow)
    }

    func testNullRateLimitDecodes() throws {
        let json = #"{"plan_type":"free","rate_limit":null}"#.data(using: .utf8)!
        let r = try JSONDecoder().decode(OpenAIUsageResponse.self, from: json)
        XCTAssertNil(r.rateLimit)
    }

    func testMissingRateLimitDecodes() throws {
        let r = try JSONDecoder().decode(OpenAIUsageResponse.self, from: "{}".data(using: .utf8)!)
        XCTAssertNil(r.rateLimit)
    }
}
