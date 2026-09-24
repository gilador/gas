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

final class UsageLogBufferTests: XCTestCase {
    func testBufferKeepsTheNewestLines() {
        let buffer = LineBuffer(capacity: 50)
        for i in 1...60 { buffer.append("line \(i)") }
        XCTAssertEqual(buffer.lines.count, 50)
        XCTAssertEqual(buffer.lines.first, "line 11")
        XCTAssertEqual(buffer.lines.last, "line 60")
    }

    func testResponseLineIsKeptForDiagnostics() {
        let url = URL(string: "https://api.anthropic.com/api/oauth/usage")!
        let response = HTTPURLResponse(url: url, statusCode: 429, httpVersion: nil, headerFields: ["Retry-After": "30"])!
        let body = #"{"error":{"type":"rate_limit_error","message":"Slow down"}}"#
        UsageLog.response(.claude, response, data: Data(body.utf8))
        XCTAssertEqual(UsageLog.recentLines().last?.hasSuffix("claude HTTP 429 retry-after=30 error=rate_limit_error: Slow down"), true)
    }
}
