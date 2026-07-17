import XCTest
@testable import UsageCore

final class ClaudeUsageDTOTests: XCTestCase {
    func testDecodesInlineSample() throws {
        let json = """
        {
          "limits": [
            {"kind":"session","group":"session","percent":62.5,"severity":"normal",
             "resets_at":"2026-01-01T18:00:00.000000+00:00","scope":null,"is_active":false},
            {"kind":"weekly_all","group":"weekly","percent":40,"severity":"normal",
             "resets_at":"2026-01-05T13:00:00.000000+00:00","scope":null,"is_active":false},
            {"kind":"weekly_scoped","group":"weekly","percent":60,"severity":"normal",
             "resets_at":"2026-01-05T13:00:00.000000+00:00",
             "scope":{"model":{"id":null,"display_name":"Claude Opus 4"}},"is_active":true}
          ]
        }
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(ClaudeUsageResponse.self, from: json)
        XCTAssertEqual(response.limits.count, 3)
        XCTAssertEqual(response.limits[0].kind, "session")
        XCTAssertEqual(response.limits[0].percent, 62.5)
        XCTAssertEqual(response.limits[0].resetsAt, "2026-01-01T18:00:00.000000+00:00")
        XCTAssertEqual(response.limits[2].scope?.model?.displayName, "Claude Opus 4")
    }

    func testDecodesRealFixture() throws {
        let r = try JSONDecoder().decode(ClaudeUsageResponse.self,
                                         from: Fixtures.data("usage_response"))
        XCTAssertEqual(r.limits.count, 3)
        XCTAssertEqual(r.limits.first?.kind, "session")
    }
}
