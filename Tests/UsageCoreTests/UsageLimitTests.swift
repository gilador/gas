import XCTest
@testable import UsageCore

final class UsageLimitTests: XCTestCase {
    func testProviderIDRawValues() {
        XCTAssertEqual(ProviderID.claude.rawValue, "claude")
        XCTAssertEqual(ProviderID.xai.rawValue, "xai")
        XCTAssertEqual(ProviderID.openai.rawValue, "openai")
    }

    func testSeverityNormalBelowWarning() {
        XCTAssertEqual(Severity.from(percent: 50, warning: 80, critical: 95), .normal)
    }

    func testSeverityWarningAtBoundary() {
        XCTAssertEqual(Severity.from(percent: 80, warning: 80, critical: 95), .warning)
    }

    func testSeverityCriticalAtBoundary() {
        XCTAssertEqual(Severity.from(percent: 95, warning: 80, critical: 95), .critical)
    }

    func testSeverityCriticalWinsWhenBothCross() {
        XCTAssertEqual(Severity.from(percent: 99, warning: 80, critical: 95), .critical)
    }

    func testUsageLimitStoresFields() {
        let limit = UsageLimit(id: "five_hour", label: "Session (5h)",
                               percentUsed: 82, resetsAt: nil, severity: .warning)
        XCTAssertEqual(limit.id, "five_hour")
        XCTAssertEqual(limit.label, "Session (5h)")
        XCTAssertEqual(limit.percentUsed, 82)
        XCTAssertNil(limit.resetsAt)
        XCTAssertEqual(limit.severity, .warning)
    }
}
