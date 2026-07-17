import WidgetKit
import SwiftUI
import UsageCore

struct UsageWidgetView: View {
    let entry: UsageEntry

    var body: some View {
        if let snapshot = entry.snapshot {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Claude Usage").font(.caption.bold())
                    Spacer()
                    if isStale(snapshot.fetchedAt) {
                        Image(systemName: "clock.badge.exclamationmark")
                            .foregroundStyle(.orange)
                    }
                }
                if displayLimits(snapshot).isEmpty {
                    Text("No data").font(.caption2).foregroundStyle(.secondary)
                } else {
                    ForEach(displayLimits(snapshot)) { bar(for: $0) }
                }
            }
            .padding(12)
        } else {
            Text("Open the app to sign in.")
                .font(.caption).padding(12)
        }
    }

    private func displayLimits(_ snapshot: UsageSnapshot) -> [UsageLimit] {
        let session = snapshot.limits.first { $0.id == "session" }
        let weekly = snapshot.limits.first { $0.id == "weekly_all" }
        return [session, weekly].compactMap { $0 }
    }

    private func isStale(_ date: Date) -> Bool {
        Date().timeIntervalSince(date) > 30 * 60
    }

    @ViewBuilder
    private func bar(for limit: UsageLimit) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(limit.label).font(.caption2)
                Spacer()
                Text("\(Int(limit.percentUsed.rounded()))%").font(.caption2.monospacedDigit())
            }
            ProgressView(value: min(limit.percentUsed, 100), total: 100)
            if let reset = limit.resetsAt {
                Text("Resets \(reset.formatted(.relative(presentation: .named)))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
