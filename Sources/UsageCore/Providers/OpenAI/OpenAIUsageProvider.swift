import Foundation

public struct OpenAIUsageProvider: UsageProvider {
    public let id: ProviderID = .openai

    private let authReader: CodexAuthReader
    private let httpClient: UsageHTTPClient
    private let baseURL: URL
    private let warningThreshold: Double
    private let criticalThreshold: Double

    public init(authReader: CodexAuthReader, httpClient: UsageHTTPClient, baseURL: URL,
                warningThreshold: Double = 80, criticalThreshold: Double = 95) {
        self.authReader = authReader
        self.httpClient = httpClient
        self.baseURL = baseURL
        self.warningThreshold = warningThreshold
        self.criticalThreshold = criticalThreshold
    }

    public func fetch() async throws -> UsageSnapshot {
        let now = Date()

        let auth: CodexAuth
        do {
            auth = try authReader.readCodexAuth()
        } catch TokenReaderError.notFound {
            return snapshot(now, .needsSignIn)
        } catch {
            return snapshot(now, .error(message: "Can't read Codex credentials"))
        }

        if let expiry = auth.expiresAt, expiry <= now {
            return snapshot(now, .stale(reason: "Token expired — open Codex to refresh"))
        }

        let url = baseURL.appendingPathComponent("backend-api/wham/usage")
        var headers = [
            "Authorization": "Bearer \(auth.accessToken)",
            "Accept": "application/json"
        ]
        if let accountID = auth.accountID, !accountID.isEmpty {
            headers["ChatGPT-Account-Id"] = accountID
        }

        do {
            let (data, response) = try await httpClient.get(url, headers: headers)
            if response.statusCode == 401 {
                return snapshot(now, .stale(reason: "Unauthorized — open Codex to refresh"))
            }
            if response.statusCode == 429 {
                return snapshot(now, .stale(reason: "Rate limited — retrying"))
            }
            guard (200..<300).contains(response.statusCode) else {
                return snapshot(now, .error(message: "HTTP \(response.statusCode)"))
            }
            let decoded = try JSONDecoder().decode(OpenAIUsageResponse.self, from: data)
            let limits = OpenAIUsageMapper.map(decoded.rateLimit,
                                               warning: warningThreshold,
                                               critical: criticalThreshold)
            return UsageSnapshot(provider: .openai, fetchedAt: now, limits: limits, status: .ok)
        } catch is URLError {
            return snapshot(now, .stale(reason: "Network unavailable — retrying"))
        } catch is DecodingError {
            return snapshot(now, .error(message: "Couldn't read usage data"))
        } catch {
            return snapshot(now, .error(message: "Unexpected error"))
        }
    }

    private func snapshot(_ now: Date, _ status: FetchStatus) -> UsageSnapshot {
        UsageSnapshot(provider: .openai, fetchedAt: now, limits: [], status: status)
    }
}
