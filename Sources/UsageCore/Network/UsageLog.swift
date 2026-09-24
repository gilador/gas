import Foundation
import os

enum UsageLog {
    private static let network = Logger(subsystem: "com.gilad.agentusage", category: "network")

    /// Status, Retry-After and the error type and message only; never headers, tokens or the raw body.
    static func response(_ provider: ProviderID, _ response: HTTPURLResponse, data: Data) {
        let retryAfter = response.value(forHTTPHeaderField: "Retry-After") ?? "-"
        var line = "\(provider.rawValue) HTTP \(response.statusCode) retry-after=\(retryAfter)"
        if !(200..<300).contains(response.statusCode) {
            line += " error=\(errorSummary(data))"
        }
        network.log("\(line, privacy: .public)")
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

    static func networkError(_ provider: ProviderID, _ error: URLError) {
        network.log("\(provider.rawValue, privacy: .public) network error \(error.code.rawValue, privacy: .public)")
    }
}
