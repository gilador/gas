enum ClaudeLocalUsageMapper {
    static func map(_ usage: ClaudeLocalUsage, warning: Double, critical: Double) -> [UsageLimit] {
        var limits: [UsageLimit] = []
        if let fiveHour = usage.fiveHour {
            limits.append(UsageLimit(id: "session", label: "Session (5h)",
                                     percentUsed: fiveHour.usedPercentage,
                                     resetsAt: fiveHour.resetsAt,
                                     severity: Severity.from(percent: fiveHour.usedPercentage,
                                                             warning: warning, critical: critical)))
        }
        if let sevenDay = usage.sevenDay {
            limits.append(UsageLimit(id: "weekly_all", label: "Weekly",
                                     percentUsed: sevenDay.usedPercentage,
                                     resetsAt: sevenDay.resetsAt,
                                     severity: Severity.from(percent: sevenDay.usedPercentage,
                                                             warning: warning, critical: critical)))
        }
        return limits
    }
}
