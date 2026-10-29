import Foundation

enum XAIUsageMapper {
    static func map(_ config: XAIBillingResponse.Config?, warning: Double, critical: Double) -> [UsageLimit] {
        guard let config, config.creditUsagePercent != nil || config.currentPeriod?.type != nil else { return [] }
        // The server's protobuf JSON leaves out a zero percent, so a known period without one means none used yet.
        let percent = config.creditUsagePercent ?? 0
        let (id, label) = period(config.currentPeriod?.type)
        return [UsageLimit(id: id, label: label, percentUsed: percent,
                           resetsAt: ClaudeDate.parse(config.currentPeriod?.end) ?? ClaudeDate.parse(config.billingPeriodEnd),
                           severity: Severity.from(percent: percent, warning: warning, critical: critical))]
    }

    private static func period(_ type: String?) -> (id: String, label: String) {
        switch type {
        case "USAGE_PERIOD_TYPE_WEEKLY": return ("weekly_all", "Weekly (Grok CLI)")
        case "USAGE_PERIOD_TYPE_MONTHLY": return ("monthly", "Monthly (Grok CLI)")
        default: return ("monthly", "Grok CLI usage")
        }
    }
}
