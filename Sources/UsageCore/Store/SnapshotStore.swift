import Foundation

public struct SnapshotStore {
    private let fileURL: URL

    public init(containerURL: URL) {
        self.fileURL = containerURL.appendingPathComponent("usage_snapshot.json")
    }

    public init(appGroupID: String) {
        let fm = FileManager.default
        let container = fm.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
            ?? fm.temporaryDirectory.appendingPathComponent(appGroupID, isDirectory: true)
        try? fm.createDirectory(at: container, withIntermediateDirectories: true)
        self.init(containerURL: container)
    }

    public func save(_ snapshot: UsageSnapshot) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: .atomic)
    }

    public func load() -> UsageSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(UsageSnapshot.self, from: data)
    }
}
