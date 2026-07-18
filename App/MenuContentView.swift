import SwiftUI
import UsageCore

struct MenuContentView: View {
    @ObservedObject var viewModel: UsageViewModel
    let onSettings: () -> Void
    @AppStorage("showDesktopPanel") private var showDesktopPanel = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let snapshot = viewModel.snapshot {
                statusRow(snapshot.status)
                if snapshot.limits.isEmpty {
                    Text("No usage data.").foregroundStyle(.secondary)
                } else {
                    ForEach(snapshot.limits) { LimitRow(limit: $0) }
                }
                Text("Updated \(snapshot.fetchedAt.formatted(.relative(presentation: .named)))")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Loading…")
            }
            Divider()
            HStack(spacing: 14) {
                Button { Task { await viewModel.refresh() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Refresh now")

                Button(action: onSettings) {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.plain)
                .help("Preferences")

                Button(action: confirmQuit) {
                    Image(systemName: "power")
                }
                .buttonStyle(.plain)
                .help("Quit")

                Spacer()

                Toggle("Floating panel", isOn: $showDesktopPanel)
                    .toggleStyle(.checkbox)
            }
        }
        .padding(12)
        .frame(width: 280)
    }

    private func confirmQuit() {
        let alert = NSAlert()
        alert.messageText = "Quit Claude Usage?"
        alert.informativeText = "The menu bar item and desktop panel will stop updating until you reopen the app."
        alert.addButton(withTitle: "Quit")
        let cancel = alert.addButton(withTitle: "Cancel")
        cancel.keyEquivalent = "\u{1b}"   // Escape cancels
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            NSApplication.shared.terminate(nil)
        }
    }

    @ViewBuilder
    private func statusRow(_ status: FetchStatus) -> some View {
        switch status {
        case .ok:
            EmptyView()
        case .stale(let reason):
            Label(reason, systemImage: "clock.badge.exclamationmark").foregroundStyle(.orange)
        case .needsSignIn:
            Label("Sign in to Claude Code first.", systemImage: "person.crop.circle.badge.questionmark")
                .foregroundStyle(.orange)
        case .keychainDenied:
            Label("Keychain access denied — grant access.", systemImage: "lock.slash")
                .foregroundStyle(.red)
        case .error(let message):
            Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
        }
    }
}

struct LimitRow: View {
    let limit: UsageLimit

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(limit.label).font(.callout)
                Spacer()
                Text("\(Int(limit.percentUsed.rounded()))%").font(.callout.monospacedDigit())
            }
            ProgressView(value: min(limit.percentUsed, 100), total: 100)
                .tint(color(for: limit.severity))
            if let reset = limit.resetsAt {
                Text("Resets \(reset.formatted(.relative(presentation: .named)))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func color(for severity: Severity) -> Color {
        switch severity {
        case .normal: return .green
        case .warning: return .orange
        case .critical: return .red
        }
    }
}
