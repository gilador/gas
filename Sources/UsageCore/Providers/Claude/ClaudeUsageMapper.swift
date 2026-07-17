import Foundation

/// Parses the `/usage` `resets_at` ISO8601 strings (which carry fractional
/// seconds) to `Date`. `JSONDecoder.iso8601` cannot handle fractional seconds,
/// so we parse in the mapper with a fractional-then-plain fallback.
enum ClaudeDate {
    private static let withFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parse(_ s: String?) -> Date? {
        guard let s = s, !s.isEmpty else { return nil }
        return withFractional.date(from: s) ?? plain.date(from: s)
    }
}

enum ClaudeUsageMapper {
    static func map(_ entries: [ClaudeUsageResponse.Entry],
                    warning: Double, critical: Double) -> [UsageLimit] {
        entries.map { entry in
            let label: String
            let id: String
            switch entry.kind {
            case "session":
                label = "Session (5h)"
                id = "session"
            case "weekly_all":
                label = "Weekly"
                id = "weekly_all"
            case "weekly_scoped":
                if let name = entry.scope?.model?.displayName {
                    label = "Weekly (\(name))"
                    id = "weekly_scoped#\(name)"
                } else {
                    label = "Weekly (scoped)"
                    id = "weekly_scoped"
                }
            default:
                label = entry.kind.replacingOccurrences(of: "_", with: " ").capitalized
                id = entry.kind
            }

            let resets = ClaudeDate.parse(entry.resetsAt)
            let severity = Severity.from(percent: entry.percent,
                                         warning: warning, critical: critical)
            return UsageLimit(id: id, label: label, percentUsed: entry.percent,
                              resetsAt: resets, severity: severity)
        }
    }
}
