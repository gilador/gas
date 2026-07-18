import SwiftUI
import UsageCore

struct DesktopPanelView: View {
    @ObservedObject var viewModel: UsageViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Claude Usage").font(.caption.bold())
            content
        }
        .padding(12)
        .frame(width: 240, alignment: .topLeading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private var content: some View {
        if let snapshot = viewModel.snapshot {
            if snapshot.limits.isEmpty {
                Text(statusText(snapshot.status)).font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(snapshot.limits) { LimitRow(limit: $0) }
            }
        } else {
            Text("Loading…").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func statusText(_ status: FetchStatus) -> String {
        switch status {
        case .ok: return "No data"
        case .stale(let reason): return reason
        case .needsSignIn: return "Sign in to Claude Code"
        case .keychainDenied: return "Keychain access denied"
        case .error(let message): return message
        }
    }
}
