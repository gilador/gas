import Foundation

public struct NotificationState: Codable, Equatable, Sendable {
    /// key: "<provider>#<limitID>#<threshold>" -> resetsAt (epoch seconds, 0 if none) it last fired for.
    public var fired: [String: Double]

    public init(fired: [String: Double] = [:]) {
        self.fired = fired
    }
}

public struct ThresholdCrossing: Equatable, Sendable {
    public let provider: ProviderID
    public let limit: UsageLimit
    public let threshold: Double

    public init(provider: ProviderID, limit: UsageLimit, threshold: Double) {
        self.provider = provider
        self.limit = limit
        self.threshold = threshold
    }
}

public enum ThresholdEvaluator {
    public static func evaluate(_ snapshot: UsageSnapshot,
                                state: inout NotificationState,
                                thresholds: [Double]) -> [ThresholdCrossing] {
        var crossings: [ThresholdCrossing] = []
        for limit in snapshot.limits {
            let window = limit.resetsAt?.timeIntervalSince1970 ?? 0
            for threshold in thresholds {
                let key = "\(snapshot.provider.rawValue)#\(limit.id)#\(threshold)"
                if limit.percentUsed >= threshold {
                    if !isSameWindow(state.fired[key], window) {
                        crossings.append(ThresholdCrossing(provider: snapshot.provider,
                                                           limit: limit, threshold: threshold))
                        state.fired[key] = window
                    }
                } else {
                    // dropped below threshold — clear so it can re-fire on the next climb.
                    state.fired[key] = nil
                }
            }
        }
        return crossings
    }

    /// Providers report the same reset time with up to a few seconds of jitter between fetches.
    private static func isSameWindow(_ fired: Double?, _ window: Double) -> Bool {
        guard let fired else { return false }
        return abs(fired - window) < 120
    }
}
