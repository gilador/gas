import SwiftUI
import UsageCore

/// One provider in the floating strip; the number follows the limit that blocks first.
struct ProviderStripItem: View {
    let snapshot: UsageSnapshot
    var alert: AlertCenter.ActiveAlert? = nil
    var horizontal = false
    @AppStorage(UsageDisplayMode.key) private var usageDisplayRaw = UsageDisplayMode.used.rawValue
    private var mode: UsageDisplayMode { .current(usageDisplayRaw) }

    private static let barSize = CGSize(width: 8, height: 84)
    private static let horizontalBarLength: CGFloat = 84

    var body: some View {
        Group {
            if horizontal { horizontalBody } else { verticalBody }
        }
        .overlay { if snapshot.status != .ok && !snapshot.limits.isEmpty { glass } }
        .help(helpText)
    }

    private var verticalBody: some View {
        VStack(spacing: 4) {
            icon
            percent
            bar
            age
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    private var horizontalBody: some View {
        HStack(spacing: 7) {
            icon
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    percent
                    Spacer(minLength: 2)
                    age
                }
                // As tall as the digits, not the line, so the icon and the padding center on what shows.
                .frame(height: 9)
                horizontalBar
            }
            .frame(width: Self.horizontalBarLength)
        }
        .padding(.horizontal, 6)
    }

    private var icon: some View {
        ProviderIcon(provider: snapshot.provider, size: 14)
            .overlay(alignment: .topTrailing) {
                if let alert {
                    TimelineView(.periodic(from: alert.start, by: AlertBlink.period)) { context in
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(alert.critical ? .red : .yellow)
                            .opacity(AlertBlink.isOn(elapsed: context.date.timeIntervalSince(alert.start)) ? 1 : 0)
                    }
                    .offset(x: 8, y: -6)
                }
            }
    }

    private var percent: some View {
        Text(percentText)
            .font(.system(size: 11, weight: .semibold).monospacedDigit())
    }

    private var age: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(RelativeAge.compact(from: snapshot.fetchedAt, now: context.date))
                .font(.system(size: 9)).foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    private func usageHelp(_ limit: UsageLimit) -> String {
        "\(limit.label): \(mode.percent(for: limit))% \(mode == .used ? "used" : "left")"
    }

    private var headline: UsageLimit? { snapshot.headlineLimit }

    private var session: UsageLimit? { snapshot.limits.first { $0.id == "session" } }

    private var weekly: UsageLimit? { snapshot.limits.first { $0.id == "weekly_all" } }

    /// The shorter fill goes in front so both layers stay visible, whichever window each one is.
    private var layers: (back: UsageLimit?, front: UsageLimit?) {
        let pair = [session, weekly].compactMap { $0 }
        let sorted = (pair.isEmpty ? [headline].compactMap { $0 } : pair)
            .sorted { mode.fraction(for: $0) > mode.fraction(for: $1) }
        return sorted.count > 1 ? (sorted[0], sorted[1]) : (nil, sorted.first)
    }

    private var scoped: UsageLimit? {
        snapshot.limits.first { $0.id.hasPrefix("weekly_scoped") }
    }

    private var percentText: String {
        headline.map { "\(mode.percent(for: $0))%" } ?? "—"
    }

    private var bar: some View {
        let (back, front) = layers
        return ZStack(alignment: .bottom) {
            Capsule().fill(.white.opacity(0.15))
            if let back {
                Capsule()
                    .fill(LimitPalette.backLayerColor(for: back))
                    .frame(height: Self.barSize.height * mode.fraction(for: back))
            }
            if let front {
                Capsule()
                    .fill(LimitPalette.frontLayerColor(for: front))
                    .frame(height: Self.barSize.height * mode.fraction(for: front))
            }
            if let weekly, back != nil {
                Color.clear
                    .frame(width: Self.barSize.width + 6, height: 10)
                    .overlay(Rectangle().fill(.white).frame(height: 2))
                    .contentShape(Rectangle())
                    .help(usageHelp(weekly))
                    .offset(y: -(Self.barSize.height * mode.fraction(for: weekly)) + 5)
            }
            if let scoped {
                Color.clear
                    .frame(width: 10, height: 10)
                    .overlay(alignment: .trailing) {
                        PointerTriangle().fill(LimitPalette.color(for: scoped)).frame(width: 6, height: 7).padding(.trailing, 1)
                    }
                    .contentShape(Rectangle())
                    .help(usageHelp(scoped))
                    .offset(x: -(Self.barSize.width / 2 + 5), y: -(Self.barSize.height * mode.fraction(for: scoped)) + 5)
            }
        }
        .frame(width: Self.barSize.width, height: Self.barSize.height)
    }

    private var horizontalBar: some View {
        let (back, front) = layers
        let length = Self.horizontalBarLength
        let thickness = Self.barSize.width + 6
        return ZStack(alignment: .leading) {
            Capsule().fill(.white.opacity(0.15))
            if let back {
                Capsule()
                    .fill(LimitPalette.backLayerColor(for: back))
                    .frame(width: length * mode.fraction(for: back))
            }
            if let front {
                Capsule()
                    .fill(LimitPalette.frontLayerColor(for: front))
                    .frame(width: length * mode.fraction(for: front))
            }
            if let weekly, back != nil {
                Color.clear
                    .frame(width: 10, height: thickness)
                    .overlay(Rectangle().fill(.white).frame(width: 2))
                    .contentShape(Rectangle())
                    .help(usageHelp(weekly))
                    .offset(x: length * mode.fraction(for: weekly) - 5)
            }
            if let scoped {
                Color.clear
                    .frame(width: 10, height: 10)
                    .overlay(alignment: .top) {
                        PointerTriangle(pointsUp: true).fill(LimitPalette.color(for: scoped))
                            .frame(width: 7, height: 6).padding(.top, 1)
                    }
                    .contentShape(Rectangle())
                    .help(usageHelp(scoped))
                    .offset(x: length * mode.fraction(for: scoped) - 5, y: thickness / 2 + 5)
            }
        }
        .frame(width: length, height: thickness)
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
            var line = "\(limit.label) · \(mode.percent(for: limit))% \(mode == .used ? "used" : "left")"
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

private struct PointerTriangle: Shape {
    var pointsUp = false

    func path(in rect: CGRect) -> Path {
        Path { path in
            if pointsUp {
                path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            } else {
                path.move(to: CGPoint(x: rect.minX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            }
            path.closeSubpath()
        }
    }
}
