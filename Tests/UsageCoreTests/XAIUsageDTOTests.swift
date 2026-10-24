import XCTest
import Foundation
@testable import UsageCore

final class XAIUsageDTOTests: XCTestCase {
    func testDecodesTheFieldsGasUses() throws {
        let config = try JSONDecoder().decode(XAIBillingResponse.self, from: try Fixtures.data("xai_billing_response")).config
        XCTAssertEqual(config?.creditUsagePercent, 42.5)
        XCTAssertEqual(config?.currentPeriod?.type, "USAGE_PERIOD_TYPE_WEEKLY")
        XCTAssertEqual(config?.currentPeriod?.end, "2026-01-12T09:00:00.000000+00:00")
        XCTAssertEqual(config?.billingPeriodEnd, "2026-02-01T00:00:00.000000+00:00")
    }

    func testMissingPercentDecodesAsNil() throws {
        let body = #"{"config":{"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY"},"onDemandCap":{"val":0}}}"#
        let config = try JSONDecoder().decode(XAIBillingResponse.self, from: Data(body.utf8)).config
        XCTAssertNil(config?.creditUsagePercent)
        XCTAssertNil(config?.currentPeriod?.end)
        XCTAssertNil(config?.billingPeriodEnd)
    }

    func testMissingConfigDecodesAsNil() throws {
        XCTAssertNil(try JSONDecoder().decode(XAIBillingResponse.self, from: Data("{}".utf8)).config)
    }

    func testIntegerPercentDecodes() throws {
        let body = #"{"config":{"creditUsagePercent":7}}"#
        XCTAssertEqual(try JSONDecoder().decode(XAIBillingResponse.self, from: Data(body.utf8)).config?.creditUsagePercent, 7)
    }
}
