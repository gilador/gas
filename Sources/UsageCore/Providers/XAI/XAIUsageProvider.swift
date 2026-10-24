import Foundation

public struct XAIUsageProvider: UsageProvider {
    public let id: ProviderID = .xai
    public let manualMinimumInterval: TimeInterval = 5 * 60 - 30

    static let renewReason = "Open Grok CLI to renew its sign-in"
    static let expiryMargin: TimeInterval = 60

    private let authReader: GrokAuthReader
    private let httpClient: UsageHTTPClient
    private let versionURL: URL
    private let now: @Sendable () -> Date
    private let warningThreshold: Double
    private let criticalThreshold: Double

    public init(authReader: GrokAuthReader, httpClient: UsageHTTPClient,
                versionURL: URL = XAIUsageProvider.defaultVersionURL,
                now: @escaping @Sendable () -> Date = { Date() },
                warningThreshold: Double = 80, criticalThreshold: Double = 95) {
        self.authReader = authReader
        self.httpClient = httpClient
        self.versionURL = versionURL
        self.now = now
        self.warningThreshold = warningThreshold
        self.criticalThreshold = criticalThreshold
    }

    public static var defaultVersionURL: URL { defaultVersionURL(environment: ProcessInfo.processInfo.environment) }

    public static func defaultVersionURL(environment: [String: String]) -> URL {
        FileGrokAuthReader.home(environment: environment).appendingPathComponent("version.json")
    }

    public func fetch() async throws -> FetchOutcome {
        let start = now()

        let auth: GrokAuth
        do {
            auth = try authReader.readGrokAuth()
        } catch GrokAuthError.notFound {
            return notSent(start, .needsSignIn)
        } catch {
            return notSent(start, .error(message: "Can't read Grok sign-in"))
        }

        if auth.expiresAt <= start.addingTimeInterval(Self.expiryMargin) {
            return notSent(start, .stale(reason: Self.renewReason))
        }

        var headers = [
            "Authorization": "Bearer \(auth.accessToken)",
            "Accept": "application/json"
        ]
        if let version = Self.clientVersion(at: versionURL) {
            headers["x-grok-client-version"] = version
        }

        return FetchOutcome(snapshot: await request(headers: headers, auth: auth, start: start), requestSent: true,
                            credentialFingerprint: auth.accountFingerprint)
    }

    public func credentialFingerprint() -> String? {
        (try? authReader.readGrokAuth())?.accountFingerprint
    }

    private func request(headers: [String: String], auth: GrokAuth, start: Date) async -> UsageSnapshot {
        do {
            let (data, response) = try await httpClient.get(GrokHTTPClient.billingURL, headers: headers)
            UsageLog.response(.xai, response, data: data)
            switch response.statusCode {
            case 401:
                return snapshot(start, .stale(reason: Self.renewReason))
            case 403:
                return snapshot(start, .error(message: "Grok denied access"))
            case 429:
                let retryAfter = RetryAfter.seconds(from: response, now: start)
                return snapshot(start, .rateLimited(until: start.addingTimeInterval(retryAfter), wait: retryAfter))
            case 200..<300:
                break
            default:
                return snapshot(start, .error(message: "HTTP \(response.statusCode)"))
            }
            let decoded = try JSONDecoder().decode(XAIBillingResponse.self, from: data)
            let limits = XAIUsageMapper.map(decoded.config, warning: warningThreshold, critical: criticalThreshold)
            guard !limits.isEmpty else {
                // An expired token gets a 200 without the percent, not a 401.
                return auth.expiresAt <= now()
                    ? snapshot(start, .stale(reason: Self.renewReason))
                    : snapshot(start, .error(message: "Grok returned no usage"))
            }
            return UsageSnapshot(provider: .xai, fetchedAt: start, limits: limits, status: .ok)
        } catch let error as URLError {
            UsageLog.networkError(.xai, error)
            return snapshot(start, .stale(reason: "Network unavailable — retrying"))
        } catch is DecodingError {
            return snapshot(start, .error(message: "Couldn't read usage data"))
        } catch {
            return snapshot(start, .error(message: "Unexpected error"))
        }
    }

    static func clientVersion(at url: URL) -> String? {
        struct VersionFile: Decodable { let version: String }
        guard let data = FileManager.default.contents(atPath: url.path), data.count <= 4096,
              let version = try? JSONDecoder().decode(VersionFile.self, from: data).version,
              (1...32).contains(version.utf8.count),
              version.unicodeScalars.allSatisfy({ $0.isASCII && (CharacterSet.alphanumerics.contains($0) || ".+-".unicodeScalars.contains($0)) })
        else { return nil }
        return version
    }

    private func notSent(_ start: Date, _ status: FetchStatus) -> FetchOutcome {
        FetchOutcome(snapshot: snapshot(start, status), requestSent: false)
    }

    private func snapshot(_ start: Date, _ status: FetchStatus) -> UsageSnapshot {
        UsageSnapshot(provider: .xai, fetchedAt: start, limits: [], status: status)
    }
}
