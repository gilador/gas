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
    /// Compact menu bar label — gauge + tightest-limit percent only, to minimize
    /// menu bar width (reset times are shown in the dropdown and desktop panel).
    static func compactLabel(for limit: UsageLimit, now: Date = Date()) -> String {
        "◐ \(Int(limit.percentUsed.rounded()))%"
    }
}
