import Foundation

public enum Severity: String, Codable, Sendable {
    case normal
    case warning
    case critical

    /// Pure severity derivation. `critical` takes precedence over `warning`.
    public static func from(percent: Double, warning: Double, critical: Double) -> Severity {
        if percent >= critical { return .critical }
        if percent >= warning { return .warning }
        return .normal
    }
}

public struct UsageLimit: Codable, Sendable, Identifiable {
    public let id: String
    public let label: String
    public let percentUsed: Double
    public let resetsAt: Date?
    public var severity: Severity

    public init(id: String, label: String, percentUsed: Double,
                resetsAt: Date?, severity: Severity) {
        self.id = id
        self.label = label
        self.percentUsed = percentUsed
        self.resetsAt = resetsAt
        self.severity = severity
    }
}
