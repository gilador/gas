import SwiftUI
import UsageCore

struct MenuBarLabelView: View {
    let snapshot: UsageSnapshot?

    var body: some View {
        if let limit = snapshot?.tightestLimit {
            Text(UsageFormatter.compactLabel(for: limit))
        } else {
            Text("◐ —")
        }
    }
}

enum UsageFormatter {
    static func compactLabel(for limit: UsageLimit, now: Date = Date()) -> String {
        let pct = Int(limit.percentUsed.rounded())
        if let reset = limit.resetsAt {
            return "◐ \(pct)% · \(relativeReset(reset, now: now))"
        }
        return "◐ \(pct)%"
    }

    static func relativeReset(_ date: Date, now: Date = Date()) -> String {
        let secs = max(0, Int(date.timeIntervalSince(now)))
        let hours = secs / 3600
        let mins = (secs % 3600) / 60
        if hours > 0 { return "\(hours)h\(String(format: "%02d", mins))m" }
        return "\(mins)m"
    }
}
