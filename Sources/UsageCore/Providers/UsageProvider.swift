import Foundation

public protocol UsageProvider: Sendable {
    var id: ProviderID { get }
    /// Seconds that must pass between two requests to this provider, whatever the app's refresh tick is.
    var minimumInterval: TimeInterval { get }
    func fetch() async throws -> UsageSnapshot
}

public extension UsageProvider { var minimumInterval: TimeInterval { 0 } }
