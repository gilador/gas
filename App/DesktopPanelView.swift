import SwiftUI
import UsageCore

struct DesktopPanelView: View {
    @ObservedObject var viewModel: UsageViewModel
    let onSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Claude Usage").font(.caption.bold())
                Spacer()
                Button(action: onSettings) {
                    Image(systemName: "gearshape")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Settings")
            }
            content
        }
        .padding(14)
        .frame(width: 240, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(red: 0.12, green: 0.22, blue: 0.34))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.white.opacity(0.18), lineWidth: 1)
        )
        .environment(\.colorScheme, .dark)
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
