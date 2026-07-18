import SwiftUI
import UsageCore

struct MenuContentView: View {
    @ObservedObject var viewModel: UsageViewModel
    let onBringPanelFront: () -> Void
    @State private var showingPreferences = false
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
            Button("Refresh now") { Task { await viewModel.refresh() } }
            Toggle("Show desktop panel", isOn: $showDesktopPanel)
            Button("Bring Panel to Front") { onBringPanelFront() }
            Button("Preferences…") { showingPreferences = true }
            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
        .padding(12)
        .frame(width: 280)
        .sheet(isPresented: $showingPreferences) {
            PreferencesView(viewModel: viewModel)
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
