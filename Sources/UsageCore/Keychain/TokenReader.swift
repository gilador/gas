import Foundation

public struct ClaudeToken: Sendable {
    public let accessToken: String
    public let expiresAt: Date?

    public init(accessToken: String, expiresAt: Date?) {
        self.accessToken = accessToken
        self.expiresAt = expiresAt
    }
}

public enum TokenReaderError: Error, Equatable {
    case notFound
    case accessDenied
    case malformed
}

public protocol TokenReader: Sendable {
    func readClaudeToken() throws -> ClaudeToken
}
