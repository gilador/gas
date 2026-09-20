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
                .font(.caption)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            ZStack {
                VStack(alignment: .leading, spacing: 4) { rows }.opacity(0.7)
                RoundedRectangle(cornerRadius: 10)
                    .fill(.ultraThinMaterial)
                    .opacity(0.85)
                    .padding(-4)
                statusOverlay
            }
        }
    }

    private var rows: some View {
        ForEach(snapshot.limits) { LimitRow(limit: $0) }
    }

    private var statusOverlay: some View {
        VStack(spacing: 2) {
            statusLabel
                .font(.caption.bold())
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text("Data from \(snapshot.fetchedAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)
    }

    private var statusLabel: some View {
        Label(statusText ?? "", systemImage: statusIcon)
            .foregroundStyle(statusColor)
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
            return "Rate limited — next try \(until.formatted(.relative(presentation: .named)))"
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
