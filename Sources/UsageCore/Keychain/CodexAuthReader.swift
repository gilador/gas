import Foundation

public struct CodexAuth: Sendable, Equatable {
    public let accessToken: String
    public let accountID: String?
    public let expiresAt: Date?

    public init(accessToken: String, accountID: String?, expiresAt: Date?) {
        self.accessToken = accessToken
        self.accountID = accountID
        self.expiresAt = expiresAt
    }
}

public protocol CodexAuthReader: Sendable {
    func readCodexAuth() throws -> CodexAuth
}

public struct FileCodexAuthReader: CodexAuthReader {
    private let fileURL: URL

    public init(fileURL: URL = FileCodexAuthReader.defaultURL) {
        self.fileURL = fileURL
    }

    public static var defaultURL: URL { defaultURL(environment: ProcessInfo.processInfo.environment) }

    public static func defaultURL(environment: [String: String]) -> URL {
        let home = environment["CODEX_HOME"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex", isDirectory: true)
        return home.appendingPathComponent("auth.json")
    }

    public func readCodexAuth() throws -> CodexAuth {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else { throw TokenReaderError.notFound }
        guard let data = fm.contents(atPath: fileURL.path) else { throw TokenReaderError.accessDenied }
        return try CodexCredentials.parse(data)
    }
}
