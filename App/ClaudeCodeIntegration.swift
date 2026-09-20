import Foundation
import UsageCore

@MainActor
final class ClaudeCodeIntegration: ObservableObject {
    enum State: Equatable {
        case notConnected
        case connected(lastUpdate: Date?)
        case failed(String)
    }

    static let enabledKey = "claudeCodeBridgeEnabled"

    var isEnabled: Bool { UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true }

    @Published private(set) var state: State = .notConnected

    private let settingsURL: URL
    private let directory: URL

    init(settingsURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json"),
         directory: URL = StorageLocation.bridgeDirectory) {
        self.settingsURL = settingsURL
        self.directory = directory
        refresh()
    }

    var bridgeURL: URL { directory.appendingPathComponent("bin/claude-statusline.sh") }
    private var previousCommandURL: URL { directory.appendingPathComponent("claude-bridge.prev") }
    private var previousStatusLineURL: URL { directory.appendingPathComponent("claude-bridge-previous.json") }
    var outputURL: URL { directory.appendingPathComponent("claude_statusline.json") }

    func refresh() {
        guard let settings = try? readSettings() else { state = .notConnected; return }
        if ClaudeCodeStatusLine.isConnected(settings: settings, bridgePath: bridgeURL.path) {
            let modified = (try? FileManager.default.attributesOfItem(atPath: outputURL.path))?[.modificationDate] as? Date
            state = .connected(lastUpdate: modified)
        } else {
            state = .notConnected
        }
    }

    func connect() {
        do {
            let settings = try readSettings()
            let result = ClaudeCodeStatusLine.connect(settings: settings, bridgePath: bridgeURL.path)
            try installBridge()
            if !result.alreadyConnected {
                if let previous = result.previousStatusLine {
                    try JSONSerialization.data(withJSONObject: previous, options: [.prettyPrinted]).write(to: previousStatusLineURL, options: .atomic)
                } else {
                    try? FileManager.default.removeItem(at: previousStatusLineURL)
                }
                if let command = result.previousCommand {
                    try (command + "\n").write(to: previousCommandURL, atomically: true, encoding: .utf8)
                } else {
                    try? FileManager.default.removeItem(at: previousCommandURL)
                }
                try backupSettings()
                try writeSettings(result.settings)
            }
            refresh()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Installs the bridge on launch when the user has Claude Code and has not turned the integration off.
    func applyEnabledState() {
        let hasClaudeCode = FileManager.default.fileExists(atPath: settingsURL.deletingLastPathComponent().path)
        refresh()
        switch (isEnabled && hasClaudeCode, state) {
        case (true, .notConnected): connect()
        case (false, .connected): disconnect()
        default: break
        }
    }

    func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
        applyEnabledState()
    }

    func disconnect() {
        do {
            let settings = try readSettings()
            let previous = (try? Data(contentsOf: previousStatusLineURL))
                .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            try writeSettings(ClaudeCodeStatusLine.disconnect(settings: settings, previousStatusLine: previous))
            for url in [previousStatusLineURL, previousCommandURL, bridgeURL, outputURL] {
                try? FileManager.default.removeItem(at: url)
            }
            refresh()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func readSettings() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return [:] }
        let data = try Data(contentsOf: settingsURL)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return object
    }

    private func writeSettings(_ settings: [String: Any]) throws {
        try FileManager.default.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: settingsURL, options: .atomic)
    }

    private func backupSettings() throws {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return }
        let backup = settingsURL.deletingLastPathComponent().appendingPathComponent("settings.json.tokens-backup")
        try? FileManager.default.removeItem(at: backup)
        try FileManager.default.copyItem(at: settingsURL, to: backup)
    }

    private func installBridge() throws {
        guard let source = Bundle.main.url(forResource: "claude-statusline-bridge", withExtension: "sh") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let fm = FileManager.default
        try fm.createDirectory(at: bridgeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fm.removeItem(at: bridgeURL)
        try fm.copyItem(at: source, to: bridgeURL)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bridgeURL.path)
    }
}
