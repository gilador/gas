import Foundation

public enum ClaudeCodeStatusLine {
    public struct ConnectResult {
        public let settings: [String: Any]
        /// The status line that was in place before, to restore on disconnect. nil when there was none or the bridge was already installed.
        public let previousStatusLine: [String: Any]?
        /// The previous command the bridge must chain to. nil when there was none or the bridge was already installed.
        public let previousCommand: String?
        public let alreadyConnected: Bool
    }

    public static func quotedCommand(bridgePath: String) -> String { "\"\(bridgePath)\"" }

    private static func matchesBridge(_ command: String?, bridgePath: String) -> Bool {
        command == bridgePath || command == quotedCommand(bridgePath: bridgePath)
    }

    public static func isConnected(settings: [String: Any], bridgePath: String) -> Bool {
        matchesBridge((settings["statusLine"] as? [String: Any])?["command"] as? String, bridgePath: bridgePath)
    }

    public static func needsRepair(settings: [String: Any], bridgePath: String) -> Bool {
        (settings["statusLine"] as? [String: Any])?["command"] as? String == bridgePath
    }

    public static func connect(settings: [String: Any], bridgePath: String) -> ConnectResult {
        let previous = settings["statusLine"] as? [String: Any]
        if isConnected(settings: settings, bridgePath: bridgePath) {
            var repaired = settings
            var statusLine = previous ?? [:]
            statusLine["command"] = quotedCommand(bridgePath: bridgePath)
            repaired["statusLine"] = statusLine
            return ConnectResult(settings: repaired, previousStatusLine: nil, previousCommand: nil, alreadyConnected: true)
        }
        var bridge: [String: Any] = ["type": "command", "command": quotedCommand(bridgePath: bridgePath)]
        if let interval = previous?["refreshInterval"] { bridge["refreshInterval"] = interval }
        if let padding = previous?["padding"] { bridge["padding"] = padding }
        var patched = settings
        patched["statusLine"] = bridge
        let previousCommand = (previous?["type"] as? String) == "command" ? previous?["command"] as? String : nil
        return ConnectResult(settings: patched, previousStatusLine: previous, previousCommand: previousCommand, alreadyConnected: false)
    }

    public static func disconnect(settings: [String: Any], previousStatusLine: [String: Any]?) -> [String: Any] {
        var patched = settings
        if let previousStatusLine { patched["statusLine"] = previousStatusLine } else { patched.removeValue(forKey: "statusLine") }
        return patched
    }
}
