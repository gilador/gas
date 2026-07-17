import Foundation

struct ClaudeCredentials: Codable, Sendable {
    struct OAuth: Codable, Sendable {
        let accessToken: String
        let expiresAt: Double?   // epoch milliseconds
    }
    let claudeAiOauth: OAuth

    var token: ClaudeToken {
        let expiry = claudeAiOauth.expiresAt.map { Date(timeIntervalSince1970: $0 / 1000) }
        return ClaudeToken(accessToken: claudeAiOauth.accessToken, expiresAt: expiry)
    }

    static func parse(_ data: Data) throws -> ClaudeToken {
        do {
            return try JSONDecoder().decode(ClaudeCredentials.self, from: data).token
        } catch {
            throw TokenReaderError.malformed
        }
    }
}
