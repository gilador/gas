import SwiftUI
import UsageCore

/// One provider in the floating strip; the number follows the limit that blocks first.
struct ProviderStripItem: View {
    let snapshot: UsageSnapshot
    var alert: AlertCenter.ActiveAlert? = nil
    var horizontal = false
    var extended = false
    @AppStorage(UsageDisplayMode.key) private var usageDisplayRaw = UsageDisplayMode.remaining.rawValue
    private var mode: UsageDisplayMode { .current(usageDisplayRaw) }

    private static let barSize = CGSize(width: 8, height: 84)
    private static let barGap: CGFloat = 2
    /// The compact bar draws 14 pt wide, because its weekly tick widens the stack; separate bars match it.
    private static let separateBarWidth: CGFloat = 14
    /// Shorter by the h/w letter row and its spacing, so both layouts are the same height.
    private static let separateBarHeight: CGFloat = barSize.height - 8

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
            if extended {
                doubleBar
            } else {
                percent
                bar
            }
            age
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    private var horizontalBody: some View {
        HStack(spacing: 7) {
            VStack(spacing: 2) {
                icon
                age
            }
            .frame(width: 34)
            if extended {
                horizontalDoubleBar
            } else {
                horizontalBar
                percent
                    .fixedSize()
            }
        }
        .padding(.horizontal, 4)
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
        percentLabel(percentText)
    }

    private func percentLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold).monospacedDigit())
    }

    private func limitPercent(_ limit: UsageLimit?) -> String {
        limit.map { "\(mode.percent(for: $0))%" } ?? "—"
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

    private var session: UsageLimit? { snapshot.sessionLimit }

    private var weekly: UsageLimit? { snapshot.weeklyLimit }

    /// A provider without a session or weekly limit gets one bar, never an empty slot.
    private var doubleBarSlots: [UsageLimit?] {
        let limits = [session, weekly].compactMap { $0 }
        if !limits.isEmpty { return limits }
        return [headline]
    }

    /// The shorter fill goes in front so both layers stay visible, whichever window each one is.
    private var layers: (back: UsageLimit?, front: UsageLimit?) {
        let pair = [session, weekly].compactMap { $0 }
        let sorted = (pair.isEmpty ? [headline].compactMap { $0 } : pair)
            .sorted { mode.fraction(for: $0) > mode.fraction(for: $1) }
        return sorted.count > 1 ? (sorted[0], sorted[1]) : (nil, sorted.first)
    }

    private var scoped: UsageLimit? { snapshot.scopedLimit }

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

    private func singleBar(_ limit: UsageLimit?) -> some View {
        ZStack(alignment: .bottom) {
            Capsule().fill(.white.opacity(0.15))
                .frame(width: Self.separateBarWidth)
            if let limit {
                Capsule()
                    .fill(LimitPalette.frontLayerColor(for: limit))
                    .frame(width: Self.separateBarWidth, height: Self.separateBarHeight * mode.fraction(for: limit))
            }
            if let scoped, let limit, limit.id == weekly?.id {
                Color.clear
                    .frame(width: 10, height: 10)
                    .overlay(alignment: .leading) {
                        PointerTriangle().fill(LimitPalette.color(for: scoped)).frame(width: 6, height: 7)
                            .rotationEffect(.degrees(180)).padding(.leading, 1)
                    }
                    .contentShape(Rectangle())
                    .help(usageHelp(scoped))
                    .offset(x: Self.separateBarWidth / 2 + 5, y: -(Self.separateBarHeight * mode.fraction(for: scoped)) + 5)
            }
        }
        .frame(width: Self.separateBarWidth, height: Self.separateBarHeight)
        .help(limit.map(usageHelp) ?? "")
    }

    private var doubleBar: some View {
        HStack(alignment: .top, spacing: 4) {
            ForEach(Array(doubleBarSlots.enumerated()), id: \.offset) { _, limit in
                VStack(spacing: 2) {
                    percentLabel(limitPercent(limit))
                        .fixedSize()
                    singleBar(limit)
                    barLetter(limit)
                }
            }
        }
    }

    /// Turned per bar rather than as a pair, so the letters stay upright.
    private var horizontalDoubleBar: some View {
        VStack(spacing: Self.barGap) {
            ForEach(Array(doubleBarSlots.enumerated()), id: \.offset) { _, limit in
                HStack(spacing: 3) {
                    barLetter(limit)
                    singleBar(limit)
                        .rotationEffect(.degrees(90))
                        .frame(width: Self.separateBarHeight, height: Self.separateBarWidth)
                    percentLabel(limitPercent(limit))
                        .fixedSize()
                        .frame(height: Self.separateBarWidth)
                }
            }
        }
    }

    private func barLetter(_ limit: UsageLimit?) -> some View {
        Text(limit?.id == "session" ? "h" : limit?.id == "weekly_all" ? "w" : "")
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: Self.separateBarWidth, height: Self.barSize.width)
    }

    /// The vertical bar turned 90° clockwise, so both layouts show exactly the same bar.
    private var horizontalBar: some View {
        bar
            .rotationEffect(.degrees(90))
            .frame(width: Self.barSize.height, height: Self.barSize.width + 6)
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
                line += " · resets \(ResetTime.text(for: reset, now: .now))"
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
        case .needsSignIn: return "Not logged in. \(snapshot.provider.signInHint)."
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
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}
