import CryptoKit
import Foundation

public struct ClaudeUsageProvider: UsageProvider {
    public let id: ProviderID = .claude
    public static let userAgent = "claude-code/2.1.281"

    private let tokenReader: TokenReader
    private let httpClient: UsageHTTPClient
    private let baseURL: URL
    private let warningThreshold: Double
    private let criticalThreshold: Double
    private let renewer: TokenRenewer?
    /// Hashes of tokens that Claude Code could not renew, kept in memory, so gas stops sending them.
    private let loggedOut = FingerprintSet()

    public init(tokenReader: TokenReader, httpClient: UsageHTTPClient, baseURL: URL,
                warningThreshold: Double = 80, criticalThreshold: Double = 95,
                renewer: TokenRenewer? = nil) {
        self.tokenReader = tokenReader
        self.httpClient = httpClient
        self.baseURL = baseURL
        self.warningThreshold = warningThreshold
        self.criticalThreshold = criticalThreshold
        self.renewer = renewer
    }

    public func fetch() async throws -> FetchOutcome {
        let now = Date()

        var token: ClaudeToken
        do {
            token = try tokenReader.readClaudeToken()
        } catch TokenReaderError.notFound {
            return notSent(now, .needsSignIn)
        } catch TokenReaderError.accessDenied {
            return notSent(now, .keychainDenied)
        } catch {
            return notSent(now, .error(message: "Keychain access error"))
        }

        if loggedOut.contains(Self.fingerprint(of: token)) {
            return notSent(now, .needsSignIn)
        }

        if let expiry = token.expiresAt, expiry <= now {
            guard let renewer, renewer.isEnabled else {
                return notSent(now, .stale(reason: "Token expired — open Claude Code to refresh"))
            }
            switch await renewer.renew() {
            case .failed:
                loggedOut.insert(Self.fingerprint(of: token))
                return notSent(now, .needsSignIn)
            case .unavailable:
                return notSent(now, .stale(reason: "Couldn't renew — open Claude Code"))
            case .renewed:
                guard let renewed = try? tokenReader.readClaudeToken(),
                      (renewed.expiresAt ?? .distantFuture) > Date() else {
                    return notSent(now, .stale(reason: "Couldn't renew — open Claude Code"))
                }
                token = renewed
            }
        }

        return await request(with: token, now: now, mayRenew: true)
    }

    private func request(with token: ClaudeToken, now: Date, mayRenew: Bool) async -> FetchOutcome {
        let url = baseURL.appendingPathComponent("api/oauth/usage")
        let headers = [
            "Authorization": "Bearer \(token.accessToken)",
            "anthropic-beta": "oauth-2025-04-20",
            "Content-Type": "application/json",
            "User-Agent": Self.userAgent
        ]

        do {
            let (data, response) = try await httpClient.get(url, headers: headers)
            UsageLog.response(.claude, response, data: data)
            if response.statusCode == 401 {
                return outcome(now, .stale(reason: "Unauthorized — open Claude Code to refresh"))
            }
            if response.statusCode == 429 {
                // The server also answers a logged-out token with 429; a renewal tells the two apart.
                if mayRenew, let renewer, renewer.isEnabled {
                    switch await renewer.renew() {
                    case .failed:
                        loggedOut.insert(Self.fingerprint(of: token))
                        return outcome(now, .needsSignIn)
                    case .renewed:
                        if let renewed = try? tokenReader.readClaudeToken(),
                           Self.fingerprint(of: renewed) != Self.fingerprint(of: token) {
                            let retried = await request(with: renewed, now: now, mayRenew: false)
                            if retried.requestSent { return retried }
                        }
                    case .unavailable:
                        break
                    }
                }
                let retryAfter = RetryAfter.seconds(from: response, now: now)
                return outcome(now, .rateLimited(until: now.addingTimeInterval(retryAfter), wait: retryAfter))
            }
            guard (200..<300).contains(response.statusCode) else {
                return outcome(now, .error(message: "HTTP \(response.statusCode)"))
            }
            let decoded = try JSONDecoder().decode(ClaudeUsageResponse.self, from: data)
            let limits = ClaudeUsageMapper.map(decoded.limits,
                                               warning: warningThreshold,
                                               critical: criticalThreshold)
            return FetchOutcome(snapshot: UsageSnapshot(provider: .claude, fetchedAt: now,
                                                        limits: limits, status: .ok), requestSent: true)
        } catch let error as URLError {
            UsageLog.networkError(.claude, error)
            return outcome(now, .stale(reason: "Network unavailable — retrying"),
                           requestSent: error.code != .notConnectedToInternet)
        } catch is DecodingError {
            return outcome(now, .error(message: "Couldn't read usage data"))
        } catch {
            return outcome(now, .error(message: "Unexpected error"))
        }
    }

    private static func fingerprint(of token: ClaudeToken) -> String {
        SHA256.hash(data: Data(token.accessToken.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    private func notSent(_ now: Date, _ status: FetchStatus) -> FetchOutcome {
        outcome(now, status, requestSent: false)
    }

    private func outcome(_ now: Date, _ status: FetchStatus, requestSent: Bool = true) -> FetchOutcome {
        FetchOutcome(snapshot: UsageSnapshot(provider: .claude, fetchedAt: now, limits: [], status: status),
                     requestSent: requestSent)
    }
}

private final class FingerprintSet: @unchecked Sendable {
    private let lock = NSLock()
    private var values: Set<String> = []

    func contains(_ value: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return values.contains(value)
    }

    func insert(_ value: String) {
        lock.lock(); defer { lock.unlock() }
        values.insert(value)
    }
}
