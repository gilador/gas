import SwiftUI
import UsageCore

struct ProviderSection: View {
    let snapshot: UsageSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(snapshot.provider.displayName)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        if snapshot.status == .ok {
            if snapshot.limits.isEmpty {
                Text("No usage data.").font(.caption).foregroundStyle(.secondary)
            } else {
                rows
            }
        } else if snapshot.limits.isEmpty {
            statusLabel
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            ZStack {
                rows.opacity(0.35)
                statusPanel
            }
        }
    }

    private var rows: some View {
        ForEach(snapshot.limits) { LimitRow(limit: $0) }
    }

    private var statusPanel: some View {
        VStack(spacing: 2) {
            statusLabel
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text("Data from \(snapshot.fetchedAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 8).fill(.ultraThinMaterial))
        .allowsHitTesting(false)
    }

    private var statusLabel: some View {
        Label(statusText ?? "", systemImage: statusIcon)
            .font(.caption).foregroundStyle(statusColor)
    }

    private var statusText: String? {
        switch snapshot.status {
        case .ok:
            return nil
        case .stale(let reason):
            return reason
        case .needsSignIn:
            return "Sign in to \(snapshot.provider.clientName) first."
        case .keychainDenied:
            return "Keychain access denied — grant access."
        case .error(let message):
            return message
        case .rateLimited(let until, _):
            return "Rate limited by \(snapshot.provider.displayName) API. Next try \(until.formatted(.relative(presentation: .named)))"
        }
    }

    private var statusIcon: String {
        switch snapshot.status {
        case .ok:
            return ""
        case .stale:
            return "clock.badge.exclamationmark"
        case .needsSignIn:
            return "person.crop.circle.badge.questionmark"
        case .keychainDenied:
            return "lock.slash"
        case .error:
            return "exclamationmark.triangle"
        case .rateLimited:
            return "hourglass"
        }
    }

    private var statusColor: Color {
        switch snapshot.status {
        case .ok:
            return .primary
        case .stale, .needsSignIn, .rateLimited:
            return .orange
        case .keychainDenied, .error:
            return .red
        }
    }
}
