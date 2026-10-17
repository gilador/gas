import Foundation

enum OpenAIUsageMapper {
    static func map(_ rateLimit: OpenAIUsageResponse.RateLimit?,
                    warning: Double, critical: Double) -> [UsageLimit] {
        guard let rateLimit else { return [] }
        let windows: [(window: OpenAIUsageResponse.Window, id: String, fallback: String)] = [
            rateLimit.primaryWindow.map { ($0, "session", "Session") },
            rateLimit.secondaryWindow.map { ($0, "weekly_all", "Weekly") },
        ].compactMap { $0 }
        let byLength = windows.map { idForLength($0.window.limitWindowSeconds) ?? $0.id }
        let ids = Set(byLength).count == byLength.count ? byLength : windows.map(\.id)
        return zip(windows, ids).map { entry, id in
            limit(entry.window, id: id, fallback: entry.fallback, warning: warning, critical: critical)
        }
    }

    private static func idForLength(_ seconds: Int?) -> String? {
        guard let seconds else { return nil }
        return seconds < 86_400 ? "session" : "weekly_all"
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
