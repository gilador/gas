import Foundation

public struct ClaudeLocalUsage: Sendable, Equatable {
    public struct Window: Sendable, Equatable {
        public let usedPercentage: Double
        public let resetsAt: Date?
        public init(usedPercentage: Double, resetsAt: Date?) {
            self.usedPercentage = usedPercentage
            self.resetsAt = resetsAt
        }
    }
    public let fiveHour: Window?
    public let sevenDay: Window?
    public let updatedAt: Date
    public init(fiveHour: Window?, sevenDay: Window?, updatedAt: Date) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.updatedAt = updatedAt
    }
}

public protocol ClaudeLocalUsageReader: Sendable {
    /// nil when there is no usable local data (file missing, unreadable, no rate_limits).
    func readLocalUsage() -> ClaudeLocalUsage?
}

public struct ClaudeStatuslineReader: ClaudeLocalUsageReader {
    private let fileURL: URL
    public init(fileURL: URL) { self.fileURL = fileURL }

    public func readLocalUsage() -> ClaudeLocalUsage? {
        guard let data = try? Data(contentsOf: fileURL),
              let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let modified = attrs[.modificationDate] as? Date else { return nil }
        return ClaudeStatuslineParser.parse(data, updatedAt: modified)
    }
}

enum ClaudeStatuslineParser {
    private struct Payload: Decodable {
        struct RateLimits: Decodable {
            struct Window: Decodable {
                let usedPercentage: Double
                let resetsAt: Double?
                enum CodingKeys: String, CodingKey { case usedPercentage = "used_percentage"; case resetsAt = "resets_at" }
            }
            let fiveHour: Window?
            let sevenDay: Window?
            enum CodingKeys: String, CodingKey { case fiveHour = "five_hour"; case sevenDay = "seven_day" }
        }
        let rateLimits: RateLimits?
        enum CodingKeys: String, CodingKey { case rateLimits = "rate_limits" }
    }

    static func parse(_ data: Data, updatedAt: Date) -> ClaudeLocalUsage? {
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
              let limits = payload.rateLimits,
              limits.fiveHour != nil || limits.sevenDay != nil else { return nil }
        func window(_ w: Payload.RateLimits.Window?) -> ClaudeLocalUsage.Window? {
            w.map { ClaudeLocalUsage.Window(usedPercentage: $0.usedPercentage,
                                            resetsAt: $0.resetsAt.map { Date(timeIntervalSince1970: $0) }) }
        }
        return ClaudeLocalUsage(fiveHour: window(limits.fiveHour), sevenDay: window(limits.sevenDay), updatedAt: updatedAt)
    }
}
