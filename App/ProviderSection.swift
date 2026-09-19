import SwiftUI
import UsageCore

struct ProviderSection: View {
    let snapshot: UsageSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(snapshot.provider.displayName)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            statusRow
            if snapshot.limits.isEmpty {
                if snapshot.status == .ok {
                    Text("No usage data.").font(.caption).foregroundStyle(.secondary)
                }
            } else {
                ForEach(snapshot.limits) { LimitRow(limit: $0) }
            }
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        switch snapshot.status {
        case .ok:
            EmptyView()
        case .stale(let reason):
            Label(reason, systemImage: "clock.badge.exclamationmark")
                .font(.caption).foregroundStyle(.orange)
        case .needsSignIn:
            Label("Sign in to \(snapshot.provider.clientName) first.",
                  systemImage: "person.crop.circle.badge.questionmark")
                .font(.caption).foregroundStyle(.orange)
        case .keychainDenied:
            Label("Keychain access denied — grant access.", systemImage: "lock.slash")
                .font(.caption).foregroundStyle(.red)
        case .error(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.caption).foregroundStyle(.red)
        }
    }
}
