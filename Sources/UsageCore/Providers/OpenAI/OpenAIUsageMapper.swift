import Foundation

enum OpenAIUsageMapper {
    static func map(_ rateLimit: OpenAIUsageResponse.RateLimit?,
                    warning: Double, critical: Double) -> [UsageLimit] {
        guard let rateLimit else { return [] }
        var limits: [UsageLimit] = []
        if let window = rateLimit.primaryWindow {
            limits.append(limit(window, id: "session", fallback: "Session",
                                warning: warning, critical: critical))
        }
        if let window = rateLimit.secondaryWindow {
            limits.append(limit(window, id: "weekly_all", fallback: "Weekly",
                                warning: warning, critical: critical))
        }
        return limits
    }

    static func label(windowSeconds: Int?, fallback: String) -> String {
        guard let seconds = windowSeconds else { return fallback }
        if seconds < 86_400 {
            return "Session (\(Int((Double(seconds) / 3600).rounded()))h)"
        }
        if seconds == 604_800 { return "Weekly" }
        return "\(Int((Double(seconds) / 86_400).rounded()))-day"
    }

    private static func limit(_ window: OpenAIUsageResponse.Window, id: String, fallback: String,
                              warning: Double, critical: Double) -> UsageLimit {
        UsageLimit(id: id,
                   label: label(windowSeconds: window.limitWindowSeconds, fallback: fallback),
                   percentUsed: window.usedPercent,
                   resetsAt: window.resetAt.map { Date(timeIntervalSince1970: $0) },
                   severity: Severity.from(percent: window.usedPercent,
                                           warning: warning, critical: critical))
    }
}
