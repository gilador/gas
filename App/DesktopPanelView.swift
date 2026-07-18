import SwiftUI
import UsageCore

struct DesktopPanelView: View {
    @ObservedObject var viewModel: UsageViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Claude Usage").font(.caption.bold())
            content
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(width: 240, height: 160, alignment: .topLeading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private var content: some View {
        if let snapshot = viewModel.snapshot {
            let shown = displayLimits(snapshot)
            if shown.isEmpty {
                Text(statusText(snapshot.status)).font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(shown) { LimitRow(limit: $0) }
            }
        } else {
            Text("Loading…").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func displayLimits(_ s: UsageSnapshot) -> [UsageLimit] {
        let session = s.limits.first { $0.id == "session" }
        let weekly = s.limits.first { $0.id == "weekly_all" }
        return [session, weekly].compactMap { $0 }
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
