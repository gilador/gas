import XCTest
@testable import UsageCore

final class ClaudeCodeStatusLineTests: XCTestCase {
    private let bridgePath = "/bridge/path.sh"

    func testConnectAddsStatusLineWhenNoneExists() {
        let settings: [String: Any] = ["model": "opus"]
        let result = ClaudeCodeStatusLine.connect(settings: settings, bridgePath: bridgePath)

        let statusLine = result.settings["statusLine"] as? [String: Any]
        XCTAssertEqual(statusLine?["type"] as? String, "command")
        XCTAssertEqual(statusLine?["command"] as? String, bridgePath)
        XCTAssertNil(statusLine?["refreshInterval"])
        XCTAssertNil(result.previousStatusLine)
        XCTAssertNil(result.previousCommand)
        XCTAssertFalse(result.alreadyConnected)
        XCTAssertEqual(result.settings["model"] as? String, "opus")
    }

    func testConnectCarriesRefreshIntervalAndRecordsPrevious() {
        let previousStatusLine: [String: Any] = ["type": "command", "command": "my-script.sh", "refreshInterval": 5]
        let settings: [String: Any] = ["statusLine": previousStatusLine]
        let result = ClaudeCodeStatusLine.connect(settings: settings, bridgePath: bridgePath)

        let statusLine = result.settings["statusLine"] as? [String: Any]
        XCTAssertEqual(statusLine?["command"] as? String, bridgePath)
        XCTAssertEqual(statusLine?["refreshInterval"] as? Int, 5)
        XCTAssertEqual(result.previousStatusLine as NSDictionary?, previousStatusLine as NSDictionary)
        XCTAssertEqual(result.previousCommand, "my-script.sh")
        XCTAssertFalse(result.alreadyConnected)
    }

    func testConnectCarriesPadding() {
        let previousStatusLine: [String: Any] = ["type": "command", "command": "my-script.sh", "padding": 2]
        let settings: [String: Any] = ["statusLine": previousStatusLine]
        let result = ClaudeCodeStatusLine.connect(settings: settings, bridgePath: bridgePath)

        let statusLine = result.settings["statusLine"] as? [String: Any]
        XCTAssertEqual(statusLine?["padding"] as? Int, 2)
    }

    func testConnectWhenAlreadyConnectedLeavesSettingsUnchanged() {
        let statusLine: [String: Any] = ["type": "command", "command": bridgePath]
        let settings: [String: Any] = ["statusLine": statusLine, "model": "opus"]
        let result = ClaudeCodeStatusLine.connect(settings: settings, bridgePath: bridgePath)

        XCTAssertTrue(result.alreadyConnected)
        XCTAssertEqual(result.settings as NSDictionary, settings as NSDictionary)
        XCTAssertNil(result.previousStatusLine)
        XCTAssertNil(result.previousCommand)
    }

    func testIsConnectedTrueAndFalse() {
        let connected: [String: Any] = ["statusLine": ["type": "command", "command": bridgePath]]
        let notConnected: [String: Any] = ["statusLine": ["type": "command", "command": "other.sh"]]
        let none: [String: Any] = [:]

        XCTAssertTrue(ClaudeCodeStatusLine.isConnected(settings: connected, bridgePath: bridgePath))
        XCTAssertFalse(ClaudeCodeStatusLine.isConnected(settings: notConnected, bridgePath: bridgePath))
        XCTAssertFalse(ClaudeCodeStatusLine.isConnected(settings: none, bridgePath: bridgePath))
    }

    func testDisconnectRestoresPreviousStatusLine() {
        let previousStatusLine: [String: Any] = ["type": "command", "command": "my-script.sh", "refreshInterval": 5]
        let settings: [String: Any] = ["statusLine": ["type": "command", "command": bridgePath], "model": "opus"]
        let result = ClaudeCodeStatusLine.disconnect(settings: settings, previousStatusLine: previousStatusLine)

        XCTAssertEqual(result["statusLine"] as? NSDictionary, previousStatusLine as NSDictionary)
        XCTAssertEqual(result["model"] as? String, "opus")
    }

    func testDisconnectWithNilPreviousRemovesStatusLine() {
        let settings: [String: Any] = ["statusLine": ["type": "command", "command": bridgePath], "model": "opus"]
        let result = ClaudeCodeStatusLine.disconnect(settings: settings, previousStatusLine: nil)

        XCTAssertNil(result["statusLine"])
        XCTAssertEqual(result["model"] as? String, "opus")
    }
}
