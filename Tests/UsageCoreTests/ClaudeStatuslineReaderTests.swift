import XCTest
import Foundation
@testable import UsageCore

final class ClaudeStatuslineReaderTests: XCTestCase {
    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - ClaudeStatuslineParser

    func testParsesFullPayloadWithBothWindows() {
        let json = """
        {
          "model": "claude-opus-4",
          "cwd": "/Users/user/dev",
          "rate_limits": {
            "five_hour": { "used_percentage": 42.5, "resets_at": 1700000000 },
            "seven_day": { "used_percentage": 10, "resets_at": 1700600000 }
          }
        }
        """.data(using: .utf8)!
        let updatedAt = Date()
        let usage = ClaudeStatuslineParser.parse(json, updatedAt: updatedAt)
        XCTAssertEqual(usage?.fiveHour?.usedPercentage, 42.5)
        XCTAssertEqual(usage?.fiveHour?.resetsAt, Date(timeIntervalSince1970: 1700000000))
        XCTAssertEqual(usage?.sevenDay?.usedPercentage, 10)
        XCTAssertEqual(usage?.sevenDay?.resetsAt, Date(timeIntervalSince1970: 1700600000))
        XCTAssertEqual(usage?.updatedAt, updatedAt)
    }

    func testMissingRateLimitsIsNil() {
        let json = "{ \"model\": \"claude-opus-4\" }".data(using: .utf8)!
        XCTAssertNil(ClaudeStatuslineParser.parse(json, updatedAt: Date()))
    }

    func testEmptyRateLimitsIsNil() {
        let json = "{ \"rate_limits\": {} }".data(using: .utf8)!
        XCTAssertNil(ClaudeStatuslineParser.parse(json, updatedAt: Date()))
    }

    func testOnlyFiveHourPresentLeavesSevenDayNil() {
        let json = """
        { "rate_limits": { "five_hour": { "used_percentage": 5, "resets_at": 1700000000 } } }
        """.data(using: .utf8)!
        let usage = ClaudeStatuslineParser.parse(json, updatedAt: Date())
        XCTAssertNotNil(usage?.fiveHour)
        XCTAssertNil(usage?.sevenDay)
    }

    func testBadJSONIsNil() {
        let json = "{".data(using: .utf8)!
        XCTAssertNil(ClaudeStatuslineParser.parse(json, updatedAt: Date()))
    }

    // MARK: - ClaudeStatuslineReader

    func testReaderReturnsUsageWithFileModificationDate() throws {
        let url = try tempDir().appendingPathComponent("claude_statusline.json")
        let json = """
        { "rate_limits": { "five_hour": { "used_percentage": 20, "resets_at": 1700000000 } } }
        """.data(using: .utf8)!
        try json.write(to: url)
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let modified = attrs[.modificationDate] as! Date

        let usage = ClaudeStatuslineReader(fileURL: url).readLocalUsage()
        XCTAssertNotNil(usage)
        XCTAssertEqual(usage?.updatedAt.timeIntervalSince1970 ?? 0,
                       modified.timeIntervalSince1970, accuracy: 1)
    }

    func testReaderReturnsNilForMissingFile() throws {
        let url = try tempDir().appendingPathComponent("missing.json")
        XCTAssertNil(ClaudeStatuslineReader(fileURL: url).readLocalUsage())
    }
}
