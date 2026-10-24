import XCTest
@testable import UsageCore

final class UsageLogTests: XCTestCase {
    private let marker = "sk-test-SECRET-MARKER-0123456789abcdef"
    private let url = URL(string: "https://api.example.com/usage")!

    private func respond(_ status: Int, headers: [String: String] = [:], body: String) {
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headers)!
        UsageLog.response(.claude, response, data: Data(body.utf8))
    }

    private func assertNoLeak(_ markers: [String], file: StaticString = #filePath, line: UInt = #line) {
        let log = UsageLog.recentLines().joined(separator: "\n")
        for marker in markers {
            XCTAssertFalse(log.contains(marker), "leaked \(marker)", file: file, line: line)
        }
    }

    func testServerErrorTextNeverReachesTheLog() {
        respond(400, body: #"{"error":{"type":"LEAKTYPE","message":"LEAKMSG \#(marker)","code":"LEAKCODE"}}"#)
        respond(500, body: #"{"error":{"code":"LEAKCODE2"}}"#)
        respond(403, body: "<html>LEAKHTML \(marker)</html>")
        assertNoLeak(["LEAKTYPE", "LEAKMSG", "LEAKCODE", "LEAKCODE2", "LEAKHTML", marker])
    }

    func testResponseLineHasCategoryRetryAfterAndSize() {
        respond(429, headers: ["Retry-After": "120"], body: String(repeating: "x", count: 512))
        XCTAssertEqual(UsageLog.recentLines().last?.hasSuffix(" claude HTTP 429 rate_limited retry-after=120 bytes=512"), true)
    }

    func testStatusCategories() {
        XCTAssertEqual(UsageLog.category(200), "ok")
        XCTAssertEqual(UsageLog.category(401), "unauthorized")
        XCTAssertEqual(UsageLog.category(403), "forbidden")
        XCTAssertEqual(UsageLog.category(429), "rate_limited")
        XCTAssertEqual(UsageLog.category(404), "client_error")
        XCTAssertEqual(UsageLog.category(503), "server_error")
    }

    func testRetryAfterIsValidatedBeforeLogging() {
        respond(429, headers: ["Retry-After": "Wed, 21 Oct 2026 07:28:00 GMT"], body: "")
        XCTAssertEqual(UsageLog.recentLines().last?.hasSuffix(" claude HTTP 429 rate_limited retry-after=date bytes=0"), true)
        respond(429, headers: ["Retry-After": "LEAKHEADER \(marker)"], body: "")
        XCTAssertEqual(UsageLog.recentLines().last?.hasSuffix(" claude HTTP 429 rate_limited retry-after=- bytes=0"), true)
        assertNoLeak(["LEAKHEADER", marker])
    }

    func testNoteRedactsBearerJWTAndLongTokens() {
        let jwt = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJMRUFLSldUIn0.c2lnbmF0dXJlLW1hcmtlcg"
        UsageLog.note("auth Bearer LEAKBEARER-abc")
        UsageLog.note("jwt \(jwt) end")
        UsageLog.note("raw \(marker) end")
        assertNoLeak(["LEAKBEARER", jwt, "eyJhbGciOiJIUzI1NiJ9", marker])
        XCTAssertEqual(UsageLog.recentLines().suffix(3).map { $0.split(separator: " ", maxSplits: 1).last.map(String.init) },
                       ["auth [redacted]", "jwt [redacted] end", "raw [redacted] end"])
    }

    func testRedactionLeavesNormalLinesAlone() {
        for line in ["claude HTTP 429 rate_limited retry-after=120 bytes=512",
                     "update check latest=1.0.30 installed=1.0.29",
                     "at 2026-10-24T07:28:00Z openai network error -1009"] {
            XCTAssertEqual(UsageLog.redact(line), line)
        }
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
}
