import Foundation

public struct ClaudeUsageProvider: UsageProvider {
    public let id: ProviderID = .claude

    private let tokenReader: TokenReader
    private let httpClient: UsageHTTPClient
    private let baseURL: URL
    private let warningThreshold: Double
    private let criticalThreshold: Double

    public init(tokenReader: TokenReader, httpClient: UsageHTTPClient, baseURL: URL,
                warningThreshold: Double = 80, criticalThreshold: Double = 95) {
        self.tokenReader = tokenReader
        self.httpClient = httpClient
        self.baseURL = baseURL
        self.warningThreshold = warningThreshold
        self.criticalThreshold = criticalThreshold
    }

    public func fetch() async throws -> UsageSnapshot {
        let now = Date()

        let token: ClaudeToken
        do {
            token = try tokenReader.readClaudeToken()
        } catch TokenReaderError.notFound {
            return snapshot(now, .needsSignIn)
        } catch TokenReaderError.accessDenied {
            return snapshot(now, .keychainDenied)
        } catch {
            return snapshot(now, .error(message: "Keychain: \(error)"))
        }

        if let expiry = token.expiresAt, expiry <= now {
            return snapshot(now, .stale(reason: "Token expired — open Claude Code to refresh"))
        }

        let url = baseURL.appendingPathComponent("api/oauth/usage")
        let headers = [
            "Authorization": "Bearer \(token.accessToken)",
            "anthropic-beta": "oauth-2025-04-20",
            "Content-Type": "application/json"
        ]

        do {
            let (data, response) = try await httpClient.get(url, headers: headers)
            if response.statusCode == 401 {
                return snapshot(now, .stale(reason: "Unauthorized — open Claude Code to refresh"))
            }
            guard (200..<300).contains(response.statusCode) else {
                return snapshot(now, .error(message: "HTTP \(response.statusCode)"))
            }
            let decoded = try JSONDecoder().decode(ClaudeUsageResponse.self, from: data)
            let limits = ClaudeUsageMapper.map(decoded.limits,
                                               warning: warningThreshold,
                                               critical: criticalThreshold)
            return UsageSnapshot(provider: .claude, fetchedAt: now, limits: limits, status: .ok)
        } catch {
            return snapshot(now, .error(message: "\(error)"))
        }
    }

    private func snapshot(_ now: Date, _ status: FetchStatus) -> UsageSnapshot {
        UsageSnapshot(provider: .claude, fetchedAt: now, limits: [], status: status)
    }
}
