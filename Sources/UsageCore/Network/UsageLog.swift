import Foundation
import os

final class LineBuffer: @unchecked Sendable {
    private let capacity: Int
    private let lock = NSLock()
    private var storage: [String] = []

    init(capacity: Int) { self.capacity = capacity }

    var lines: [String] { lock.lock(); defer { lock.unlock() }; return storage }

    func append(_ line: String) {
        lock.lock(); defer { lock.unlock() }
        storage.append(line)
        if storage.count > capacity { storage.removeFirst(storage.count - capacity) }
    }
}

public enum UsageLog {
    private static let network = Logger(subsystem: "com.gilad.agentusage", category: "network")
    private static let recent = LineBuffer(capacity: 50)
    private static let secretPatterns = [
        #"Bearer\s+\S+"#,
        #"[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}"#,
        #"[A-Za-z0-9_\-+/=]{32,}"#
    ].map { try! NSRegularExpression(pattern: $0) }

    public static func recentLines() -> [String] { recent.lines }

    /// Only what gas derives itself: status, its category, a validated Retry-After and the body size.
    static func response(_ provider: ProviderID, _ response: HTTPURLResponse, data: Data) {
        let retryAfter = RetryAfter.logValue(response.value(forHTTPHeaderField: "Retry-After"))
        record("\(provider.rawValue) HTTP \(response.statusCode) \(category(response.statusCode)) retry-after=\(retryAfter) bytes=\(data.count)")
    }

    static func networkError(_ provider: ProviderID, _ error: URLError) {
        record("\(provider.rawValue) network error \(error.code.rawValue)")
    }

    static func category(_ status: Int) -> String {
        switch status {
        case 200..<300: return "ok"
        case 401: return "unauthorized"
        case 403: return "forbidden"
        case 429: return "rate_limited"
        case 400..<500: return "client_error"
        case 500..<600: return "server_error"
        default: return "other"
        }
    }

    static func redact(_ line: String) -> String {
        secretPatterns.reduce(line) { text, pattern in
            pattern.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text),
                                             withTemplate: "[redacted]")
        }
    }

    public static func note(_ line: String) { record(line) }

    private static func record(_ line: String) {
        let safe = redact(line)
        network.log("\(safe, privacy: .public)")
        recent.append("\(ISO8601DateFormatter().string(from: Date())) \(safe)")
    }
}
