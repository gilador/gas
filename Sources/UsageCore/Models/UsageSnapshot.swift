import Foundation

public enum FetchStatus: Codable, Sendable, Equatable {
    case ok
    case stale(reason: String)
    case needsSignIn
    case keychainDenied
    case error(message: String)
    case rateLimited(until: Date, wait: TimeInterval)

    /// Problems the setup window can fix, as opposed to ones that pass by themselves.
    public var needsSetup: Bool {
        self == .needsSignIn || self == .keychainDenied
    }
}

public struct UsageSnapshot: Codable, Sendable, Equatable {
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

    /// The limit that decides whether the provider can be used: the most-used provider-wide limit.
    /// Per-model limits (`weekly_scoped#…`) block only one model, so they count only when alone.
    public var headlineLimit: UsageLimit? {
        let providerWide = limits.filter { !$0.id.hasPrefix("weekly_scoped") }
        return (providerWide.isEmpty ? limits : providerWide).max(by: { $0.percentUsed < $1.percentUsed })
    }

    public var sessionLimit: UsageLimit? { limits.first { $0.id == "session" } }

    public var weeklyLimit: UsageLimit? { limits.first { $0.id == "weekly_all" } }

    public var scopedLimit: UsageLimit? { limits.first { $0.id.hasPrefix("weekly_scoped") } }

    /// Keeps the previous good limits (and their timestamp) when a refresh fails transiently.
    public func mergingLastGood(previous: UsageSnapshot?) -> UsageSnapshot {
        guard let previous, previous.provider == provider,
              !previous.limits.isEmpty, limits.isEmpty else { return self }
        switch status {
        case .stale, .error, .rateLimited:
            return UsageSnapshot(provider: provider, fetchedAt: previous.fetchedAt,
                                 limits: previous.limits, status: status)
        case .ok, .needsSignIn, .keychainDenied:
            return self
        }
    }
}
