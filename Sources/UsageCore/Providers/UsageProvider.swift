public protocol UsageProvider: Sendable {
    var id: ProviderID { get }
    var servesLocally: Bool { get }
    func fetch() async throws -> UsageSnapshot
}

public extension UsageProvider {
    var servesLocally: Bool { false }
}
