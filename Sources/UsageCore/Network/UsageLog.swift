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

    public static func recentLines() -> [String] { recent.lines }

    /// Status, Retry-After and the error type and message only; never headers, tokens or the raw body.
    static func response(_ provider: ProviderID, _ response: HTTPURLResponse, data: Data) {
        let retryAfter = response.value(forHTTPHeaderField: "Retry-After") ?? "-"
        var line = "\(provider.rawValue) HTTP \(response.statusCode) retry-after=\(retryAfter)"
        if !(200..<300).contains(response.statusCode) {
            line += " error=\(errorSummary(data))"
        }
        record(line)
    }

    static func networkError(_ provider: ProviderID, _ error: URLError) {
        record("\(provider.rawValue) network error \(error.code.rawValue)")
    }

    static func errorSummary(_ data: Data) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any],
              let type = (error["type"] ?? error["code"]) as? String else {
            return "unrecognized body (\(data.count) bytes)"
        }
        guard let message = error["message"] as? String, !message.isEmpty else { return type }
        return "\(type): \(message.prefix(200))"
    }

    private static func record(_ line: String) {
        network.log("\(line, privacy: .public)")
        recent.append("\(ISO8601DateFormatter().string(from: Date())) \(line)")
    }
}
