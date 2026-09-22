import SwiftUI
import UsageCore

/// One provider in the floating strip: session percent, a thin bar for the session limit, a tick for the weekly one.
struct ProviderStripItem: View {
    let snapshot: UsageSnapshot

    private static let barSize = CGSize(width: 8, height: 84)

    var body: some View {
        VStack(spacing: 4) {
            ProviderIcon(provider: snapshot.provider, size: 14)
            Text(percentText)
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
            bar
            TimelineView(.periodic(from: .now, by: 30)) { _ in
                Text(snapshot.fetchedAt.formatted(.relative(presentation: .named, unitsStyle: .narrow)))
                    .font(.system(size: 9)).foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .overlay { if snapshot.status != .ok && !snapshot.limits.isEmpty { glass } }
        .help(helpText)
    }

    private var session: UsageLimit? {
        snapshot.limits.first { $0.id == "session" } ?? snapshot.tightestLimit
    }

    private var weekly: UsageLimit? {
        snapshot.limits.first { $0.id == "weekly_all" }
    }

    private var percentText: String {
        session.map { "\($0.displayPercent)%" } ?? "—"
    }

    private var bar: some View {
        ZStack(alignment: .bottom) {
            Capsule().fill(.white.opacity(0.15))
            if let session {
                Capsule()
                    .fill(LimitPalette.color(for: session))
                    .frame(height: Self.barSize.height * min(session.percentUsed, 100) / 100)
            }
            if let weekly {
                Color.clear
                    .frame(width: Self.barSize.width + 6, height: 10)
                    .overlay(Rectangle().fill(LimitPalette.color(for: weekly)).frame(height: 2))
                    .contentShape(Rectangle())
                    .help("Weekly: \(weekly.displayPercent)%")
                    .offset(y: -(Self.barSize.height * min(weekly.percentUsed, 100) / 100) + 5)
            }
        }
        .frame(width: Self.barSize.width, height: Self.barSize.height)
    }

    private var glass: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(.ultraThinMaterial).opacity(0.85)
            Image(systemName: statusIcon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(statusColor)
                .padding(5)
                .background(RoundedRectangle(cornerRadius: 6).fill(.black.opacity(0.6)))
        }
        .allowsHitTesting(false)
    }

    private var helpText: String {
        var lines = snapshot.limits.map { limit -> String in
            var line = "\(limit.label) · \(limit.displayPercent)%"
            if let reset = limit.resetsAt {
                line += " · resets \(reset.formatted(.relative(presentation: .named)))"
            }
            return line
        }
        if let status = statusText { lines.insert(status, at: 0) }
        lines.append("Data from \(snapshot.fetchedAt.formatted(date: .abbreviated, time: .shortened))")
        return lines.joined(separator: "\n")
    }

    private var statusText: String? {
        switch snapshot.status {
        case .ok: return nil
        case .stale(let reason): return reason
        case .needsSignIn: return "Sign in to \(snapshot.provider.clientName) first."
        case .keychainDenied: return "Keychain access denied — grant access."
        case .error(let message): return message
        case .rateLimited(let until, _):
            return "Rate limited — next try \(until.formatted(.relative(presentation: .named)))"
        }
    }

    private var statusIcon: String {
        switch snapshot.status {
        case .ok: return ""
        case .stale: return "clock.badge.exclamationmark"
        case .needsSignIn: return "person.crop.circle.badge.questionmark"
        case .keychainDenied: return "lock.slash"
        case .error: return "exclamationmark.triangle"
        case .rateLimited: return "hourglass"
        }
    }

    private var statusColor: Color {
        switch snapshot.status {
        case .ok: return .primary
        case .stale, .needsSignIn, .rateLimited: return .orange
        case .keychainDenied, .error: return .red
        }
    }
}
