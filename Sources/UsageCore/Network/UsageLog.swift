import Foundation
import os

enum UsageLog {
    private static let network = Logger(subsystem: "com.gilad.agentusage", category: "network")

    /// Status, Retry-After and the error body only; never headers or tokens.
    static func response(_ provider: ProviderID, _ response: HTTPURLResponse, data: Data) {
        let retryAfter = response.value(forHTTPHeaderField: "Retry-After") ?? "-"
        var line = "\(provider.rawValue) HTTP \(response.statusCode) retry-after=\(retryAfter)"
        if !(200..<300).contains(response.statusCode) {
            line += " body=\(String(decoding: data.prefix(300), as: UTF8.self))"
        }
        network.log("\(line, privacy: .public)")
    }

    static func networkError(_ provider: ProviderID, _ error: URLError) {
        network.log("\(provider.rawValue, privacy: .public) network error \(error.code.rawValue, privacy: .public)")
    }
}
