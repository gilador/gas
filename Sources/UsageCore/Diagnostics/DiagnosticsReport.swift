import Foundation
import Security

public struct KeychainEntrySummary: Equatable, Sendable {
    public let service: String
    public let account: String
    public let modified: Date?

    public init(service: String, account: String, modified: Date?) {
        self.service = service
        self.account = account
        self.modified = modified
    }
}

/// A plain-text report a user can paste into a chat; holds no tokens.
public enum DiagnosticsReport {
    public static func tokenStatus(_ result: Result<ClaudeToken, Error>, now: Date) -> String {
        switch result {
        case .success(let token):
            guard let expiry = token.expiresAt else { return "ok · no expiry" }
            return expiry > now ? "ok · expires \(iso(expiry))" : "expired · \(iso(expiry))"
        case .failure(TokenReaderError.notFound): return "not found"
        case .failure(TokenReaderError.accessDenied): return "access denied"
        case .failure: return "unreadable"
        }
    }

    public static func render(appVersion: String, osVersion: String, now: Date,
                              keychainEntries: [KeychainEntrySummary], tokenStatus: String,
                              board: UsageBoard, recentLog: [String]) -> String {
        var lines = ["gas \(appVersion) · macOS \(osVersion) · \(iso(now))", "", "== Keychain (Claude Code entries, names only)"]
        if keychainEntries.isEmpty { lines.append("no Claude Code entries") }
        for entry in keychainEntries {
            lines.append("\(entry.service) · account \(entry.account) · modified \(entry.modified.map(iso) ?? "?")")
        }
        lines.append("gas reads: Claude Code-credentials · \(tokenStatus)")
        lines += ["", "== State", boardJSON(board), "", "== Requests since launch (newest last)"]
        lines += recentLog.isEmpty ? ["no requests since launch"] : recentLog
        return lines.joined(separator: "\n")
    }

    private static func boardJSON(_ board: UsageBoard) -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(board)).map { String(decoding: $0, as: UTF8.self) } ?? "unreadable"
    }

    private static func iso(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }
}

public enum ClaudeKeychainEntries {
    /// Attributes only, so no Keychain prompt; newest change first.
    public static func list() -> [KeychainEntrySummary] {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecMatchLimit as String: kSecMatchLimitAll,
                                    kSecReturnAttributes as String: true]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]] else { return [] }
        return items.compactMap { item -> KeychainEntrySummary? in
            guard let service = item[kSecAttrService as String] as? String, service.hasPrefix("Claude Code") else { return nil }
            return KeychainEntrySummary(service: service,
                                        account: item[kSecAttrAccount as String] as? String ?? "?",
                                        modified: item[kSecAttrModificationDate as String] as? Date)
        }
        .sorted { ($0.modified ?? .distantPast) > ($1.modified ?? .distantPast) }
    }
}
