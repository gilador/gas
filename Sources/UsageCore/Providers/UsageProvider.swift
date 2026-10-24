import Foundation

public struct FetchOutcome: Sendable, Equatable {
    public let snapshot: UsageSnapshot
    /// True when a request reached the network, so it counts toward the provider's limits.
    public let requestSent: Bool
    /// The account behind the credential that was sent; nil when the credential names none.
    public let credentialFingerprint: String?

    public init(snapshot: UsageSnapshot, requestSent: Bool, credentialFingerprint: String? = nil) {
        self.snapshot = snapshot
        self.requestSent = requestSent
        self.credentialFingerprint = credentialFingerprint
    }
}

public protocol UsageProvider: Sendable {
    var id: ProviderID { get }
    /// Seconds that must pass between two requests to this provider, whatever the app's refresh tick is.
    var minimumInterval: TimeInterval { get }
    /// Debounce for manual (user-triggered) refreshes.
    var manualMinimumInterval: TimeInterval { get }
    func fetch() async throws -> FetchOutcome
    /// The account of the current credential, so signing in to another account can end a rate-limit wait; nil when unknown.
    func credentialFingerprint() -> String?
}

public extension UsageProvider {
    /// Just under the 5-minute tick, so timer jitter does not skip every second call.
    var minimumInterval: TimeInterval { 5 * 60 - 30 }
    var manualMinimumInterval: TimeInterval { 60 }
    func credentialFingerprint() -> String? { nil }
}
