import WidgetKit
import SwiftUI
import UsageCore

struct UsageWidgetView: View {
    let entry: UsageEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let board = entry.board, !board.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Tokens").font(.caption.bold())
                    Spacer()
                    if let fetched = board.latestFetchedAt, isStale(fetched) {
                        Image(systemName: "clock.badge.exclamationmark")
                            .foregroundStyle(.orange)
                    }
                }
                if family == .systemSmall {
                    smallRows(board)
                } else {
                    mediumRows(board)
                }
            }
            .padding(12)
        } else {
            Text("Open the app to sign in.")
                .font(.caption).padding(12)
        }
    }

    @ViewBuilder
    private func smallRows(_ board: UsageBoard) -> some View {
        if board.tightestLimits.isEmpty {
            Text("No data").font(.caption2).foregroundStyle(.secondary)
        } else {
            ForEach(board.tightestLimits, id: \.provider) { item in
                bar(for: item.limit, title: "\(item.provider.glyph) \(item.provider.displayName)")
            }
        }
    }

    @ViewBuilder
    private func mediumRows(_ board: UsageBoard) -> some View {
        ForEach(board.snapshots, id: \.provider) { snapshot in
            Text(snapshot.provider.displayName).font(.caption2.bold()).foregroundStyle(.secondary)
            let limits = displayLimits(snapshot)
            if limits.isEmpty {
                Text("No data").font(.caption2).foregroundStyle(.secondary)
            } else {
                ForEach(limits) { bar(for: $0, title: $0.label) }
            }
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
    private func bar(for limit: UsageLimit, title: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.caption2)
                Spacer()
                Text("\(limit.displayPercent)%").font(.caption2.monospacedDigit())
            }
            ProgressView(value: min(limit.percentUsed, 100), total: 100)
            if let reset = limit.resetsAt {
                Text("Resets \(reset.formatted(.relative(presentation: .named)))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
