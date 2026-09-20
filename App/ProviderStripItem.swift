import SwiftUI
import UsageCore

/// One provider in the floating strip: percent, a thin bar for the tightest limit, a tick for the other one.
struct ProviderStripItem: View {
    let snapshot: UsageSnapshot

    private static let barSize = CGSize(width: 8, height: 84)

    var body: some View {
        VStack(spacing: 4) {
            Text(percentText)
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
            bar
            Text(snapshot.provider.glyph).font(.system(size: 12))
            Text(snapshot.fetchedAt.formatted(.relative(presentation: .numeric, unitsStyle: .narrow)))
                .font(.system(size: 9)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .overlay { if snapshot.status != .ok { glass } }
        .help(helpText)
    }

    private var tightest: UsageLimit? { snapshot.tightestLimit }

    private var other: UsageLimit? {
        let mains = snapshot.limits.filter { $0.id == "session" || $0.id == "weekly_all" }
        return mains.first { $0.id != tightest?.id }
    }

    private var percentText: String {
        tightest.map { "\(Int($0.percentUsed.rounded()))%" } ?? "—"
    }

    private var bar: some View {
        ZStack(alignment: .bottom) {
            Capsule().fill(.white.opacity(0.15))
            if let tightest {
                Capsule()
                    .fill(color(for: tightest.severity))
                    .frame(height: Self.barSize.height * min(tightest.percentUsed, 100) / 100)
            }
            if let other {
                Rectangle()
                    .fill(.white)
                    .frame(width: Self.barSize.width + 6, height: 2)
                    .offset(y: -(Self.barSize.height * min(other.percentUsed, 100) / 100))
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
            var line = "\(limit.label) · \(Int(limit.percentUsed.rounded()))%"
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

    private func color(for severity: Severity) -> Color {
        switch severity {
        case .normal: return .green
        case .warning: return .orange
        case .critical: return .red
        }
    }
}
