import Foundation

public struct SnapshotStore {
    private let fileURL: URL
    private let legacyURL: URL

    public init(containerURL: URL) {
        self.fileURL = containerURL.appendingPathComponent("usage_board.json")
        self.legacyURL = containerURL.appendingPathComponent("usage_snapshot.json")
    }

    public init(appGroupID: String) {
        let fm = FileManager.default
        let container = fm.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
            ?? fm.temporaryDirectory.appendingPathComponent(appGroupID, isDirectory: true)
        try? fm.createDirectory(at: container, withIntermediateDirectories: true)
        self.init(containerURL: container)
    }

    public func save(_ board: UsageBoard) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(board)
        try data.write(to: fileURL, options: .atomic)
    }

    public func load() -> UsageBoard? {
        var board = decode(UsageBoard.self, from: fileURL) ?? UsageBoard()
        if let legacy = decode(UsageSnapshot.self, from: legacyURL) {
            if let current = board.snapshot(for: legacy.provider) {
                board.replace(current.mergingLastGood(previous: legacy))
            } else {
                board.replace(legacy)
            }
        }
        return board.isEmpty ? nil : board
    }

    private func decode<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(type, from: data)
    }
}
