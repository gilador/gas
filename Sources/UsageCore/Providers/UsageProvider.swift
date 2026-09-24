import Foundation

public protocol UsageProvider: Sendable {
    var id: ProviderID { get }
    /// Seconds that must pass between two requests to this provider, whatever the app's refresh tick is.
    var minimumInterval: TimeInterval { get }
    /// Debounce for manual (user-triggered) refreshes.
    var manualMinimumInterval: TimeInterval { get }
    func fetch() async throws -> UsageSnapshot
    /// A hash of the credential in use, so a new sign-in can end a rate-limit wait; nil when unknown.
    func credentialFingerprint() -> String?
}

public extension UsageProvider {
    var minimumInterval: TimeInterval { 0 }
    var manualMinimumInterval: TimeInterval { 60 }
    func credentialFingerprint() -> String? { nil }
}
