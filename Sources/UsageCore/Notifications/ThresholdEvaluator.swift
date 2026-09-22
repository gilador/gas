import Foundation

public enum AlertLevel: String, Codable, Sendable {
    case warning, critical
}

public struct NotificationState: Codable, Equatable, Sendable {
    /// key: "<provider>#<limitID>#<level>" -> resetsAt (epoch seconds, 0 if none) of the window it fired in.
    public var fired: [String: Double]

    public init(fired: [String: Double] = [:]) {
        self.fired = fired
    }
}

public struct ThresholdCrossing: Equatable, Sendable {
    public let provider: ProviderID
    public let limit: UsageLimit
    public let level: AlertLevel
    public let threshold: Double

    public init(provider: ProviderID, limit: UsageLimit, level: AlertLevel, threshold: Double) {
        self.provider = provider
        self.limit = limit
        self.level = level
        self.threshold = threshold
    }
}

/// One alert per limit, per level, per reset window. Only a new reset window re-arms a flag,
/// so moving a threshold or a dip in the reading never repeats an alert.
public enum ThresholdEvaluator {
    public static func evaluate(_ snapshot: UsageSnapshot,
                                state: inout NotificationState,
                                warning: Double,
                                critical: Double) -> [ThresholdCrossing] {
        var crossings: [ThresholdCrossing] = []
        for limit in snapshot.limits {
            let window = limit.resetsAt?.timeIntervalSince1970 ?? 0
            for (level, threshold) in [(AlertLevel.warning, warning), (AlertLevel.critical, critical)]
            where limit.percentUsed >= threshold {
                let key = "\(snapshot.provider.rawValue)#\(limit.id)#\(level.rawValue)"
                guard !isSameWindow(state.fired[key], window) else { continue }
                crossings.append(ThresholdCrossing(provider: snapshot.provider, limit: limit,
                                                   level: level, threshold: threshold))
                state.fired[key] = window
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
