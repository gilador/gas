import Foundation

public enum FetchStatus: Codable, Sendable, Equatable {
    case ok
    case stale(reason: String)
    case needsSignIn
    case keychainDenied
    case error(message: String)
}

public struct UsageSnapshot: Codable, Sendable {
    public let provider: ProviderID
    public let fetchedAt: Date
    public let limits: [UsageLimit]
    public let status: FetchStatus

    public init(provider: ProviderID, fetchedAt: Date,
                limits: [UsageLimit], status: FetchStatus) {
        self.provider = provider
        self.fetchedAt = fetchedAt
        self.limits = limits
        self.status = status
    }

    /// The limit closest to being exhausted (highest `percentUsed`).
    public var tightestLimit: UsageLimit? {
        limits.max(by: { $0.percentUsed < $1.percentUsed })
    }
}
