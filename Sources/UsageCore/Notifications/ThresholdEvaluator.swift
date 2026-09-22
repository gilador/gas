import Foundation

public enum AlertLevel: String, Codable, Sendable {
    case warning, critical
}

public struct NotificationState: Codable, Equatable, Sendable {
    /// key: "<provider>#<limitID>#<level>" -> resetsAt (epoch seconds, 0 if none) of the window it fired in.
    public var fired: [String: Double]
    /// Same key -> the threshold value the flag fired at; a different current value re-arms the flag.
    public var firedThresholds: [String: Double]

    public init(fired: [String: Double] = [:], firedThresholds: [String: Double] = [:]) {
        self.fired = fired
        self.firedThresholds = firedThresholds
    }

    enum CodingKeys: String, CodingKey { case fired, firedThresholds }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fired = try container.decode([String: Double].self, forKey: .fired)
        firedThresholds = try container.decodeIfPresent([String: Double].self, forKey: .firedThresholds) ?? [:]
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

/// One alert per limit, per level, per reset window. A new reset window or a changed threshold
/// re-arms a flag; a dip in the reading does not.
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
                let thresholdChanged = state.firedThresholds[key].map { $0 != threshold } ?? false
                guard thresholdChanged || !isSameWindow(state.fired[key], window) else { continue }
                crossings.append(ThresholdCrossing(provider: snapshot.provider, limit: limit,
                                                   level: level, threshold: threshold))
                state.fired[key] = window
                state.firedThresholds[key] = threshold
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
