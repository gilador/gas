import Foundation

public struct ProviderLimit: Equatable, Sendable {
    public let provider: ProviderID
    public let limit: UsageLimit

    public init(provider: ProviderID, limit: UsageLimit) {
        self.provider = provider
        self.limit = limit
    }
}

public struct UsageBoard: Codable, Sendable, Equatable {
    public private(set) var snapshots: [UsageSnapshot]

    public init(snapshots: [UsageSnapshot] = []) {
        self.snapshots = []
        for snapshot in snapshots { replace(snapshot) }
    }

    public var isEmpty: Bool { snapshots.isEmpty }

    public func snapshot(for provider: ProviderID) -> UsageSnapshot? {
        snapshots.first { $0.provider == provider }
    }

    public mutating func replace(_ snapshot: UsageSnapshot) {
        snapshots.removeAll { $0.provider == snapshot.provider }
        snapshots.append(snapshot)
        snapshots.sort { Self.rank($0.provider) < Self.rank($1.provider) }
    }

    public var tightestLimits: [ProviderLimit] {
        snapshots.compactMap { snapshot in
            snapshot.tightestLimit.map { ProviderLimit(provider: snapshot.provider, limit: $0) }
        }
    }

    public var latestFetchedAt: Date? {
        snapshots.map(\.fetchedAt).max()
    }

    private static func rank(_ provider: ProviderID) -> Int {
        ProviderID.displayOrder.firstIndex(of: provider) ?? Int.max
    }
}
