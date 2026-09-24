import XCTest
@testable import UsageCore

final class UsageLogTests: XCTestCase {
    func testErrorSummaryKeepsOnlyTypeAndMessage() {
        let body = #"{"type":"error","error":{"type":"rate_limit_error","message":"Rate limited."},"request_id":"req_1","email":"a@b.c"}"#
        XCTAssertEqual(UsageLog.errorSummary(Data(body.utf8)), "rate_limit_error: Rate limited.")
    }

    func testErrorSummaryCutsLongMessages() {
        let body = #"{"error":{"type":"t","message":""# + String(repeating: "x", count: 500) + #""}}"#
        XCTAssertEqual(UsageLog.errorSummary(Data(body.utf8)), "t: " + String(repeating: "x", count: 200))
    }

    func testErrorSummaryHidesUnknownBodies() {
        XCTAssertEqual(UsageLog.errorSummary(Data("<html>a@b.c</html>".utf8)), "unrecognized body (18 bytes)")
    }
}
