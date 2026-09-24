import SwiftUI
import UsageCore

struct MenuContentView: View {
    @ObservedObject var viewModel: UsageViewModel
    let onSettings: () -> Void
    @AppStorage("showDesktopPanel") private var showDesktopPanel = false
    @State private var copiedDiagnostics = false
    @AppStorage(ProviderSettings.key(.claude)) private var claudeEnabled = true
    @AppStorage(ProviderSettings.key(.openai)) private var openaiEnabled = true

    var body: some View {
        let _ = (claudeEnabled, openaiEnabled)
        VStack(alignment: .leading, spacing: 8) {
            Text("g · a · s")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
            Divider()
            if viewModel.board.isEmpty {
                Text("Loading…")
            } else {
                ForEach(Array(viewModel.visibleSnapshots.enumerated()), id: \.element.provider) { index, snapshot in
                    if index > 0 { Divider() }
                    ProviderSection(snapshot: snapshot, nextRefresh: viewModel.nextRefresh(for: snapshot.provider),
                                    onRetry: { Task { await viewModel.refresh(manual: true) } })
                }
                if let updated = viewModel.board.latestFetchedAt {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text("Updated \(RelativeAge.compact(from: updated, now: context.date))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Divider()
            HStack(spacing: 14) {
                Button { Task { await viewModel.refresh(manual: true) } } label: {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        ZStack {
                            Image(systemName: "arrow.clockwise")
                            if let end = viewModel.manualDebounceEnd(now: context.date) {
                                let remaining = max(0, end.timeIntervalSince(context.date))
                                PieWedge(fraction: min(1, remaining / 60))
                                    .fill(.white.opacity(0.3))
                                    .frame(width: 22, height: 22)
                            }
                        }
                    }
                    .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help("Refresh now")

                Button(action: onSettings) {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.plain)
                .help("Preferences")

                Button(action: copyDiagnostics) {
                    Image(systemName: copiedDiagnostics ? "checkmark" : "stethoscope")
                }
                .buttonStyle(.plain)
                .help("Copy diagnostics")

                Button(action: confirmQuit) {
                    Image(systemName: "power")
                }
                .buttonStyle(.plain)
                .help("Quit")

                Spacer()

                Toggle("Floating panel", isOn: $showDesktopPanel)
                    .toggleStyle(.checkbox)
            }
        }
        .padding(12)
        .frame(width: 280)
    }

    private func copyDiagnostics() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(viewModel.diagnosticsReport(), forType: .string)
        copiedDiagnostics = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copiedDiagnostics = false }
    }

    private func confirmQuit() {
        let alert = NSAlert()
        alert.messageText = "Quit gas?"
        alert.informativeText = "The menu bar item and desktop panel will stop updating until you reopen the app."
        alert.addButton(withTitle: "Quit")
        let cancel = alert.addButton(withTitle: "Cancel")
        cancel.keyEquivalent = "\u{1b}"   // Escape cancels
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            NSApplication.shared.terminate(nil)
        }
    }
}

struct LimitRow: View {
    let limit: UsageLimit
    @AppStorage(UsageDisplayMode.key) private var usageDisplayRaw = UsageDisplayMode.used.rawValue
    private var mode: UsageDisplayMode { .current(usageDisplayRaw) }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(limit.label).font(.callout)
                Spacer()
                Text("\(mode.percent(for: limit))%" + (mode == .remaining ? " left" : "")).font(.callout.monospacedDigit())
            }
            LimitBar(fraction: mode.fraction(for: limit), color: LimitPalette.color(for: limit))
            if let reset = limit.resetsAt {
                Text("Resets \(reset.formatted(.relative(presentation: .named)))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

/// A pie slice from 12 o'clock whose leading edge sweeps clockwise as `fraction` shrinks to zero.
struct PieWedge: Shape {
    var fraction: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard fraction > 0 else { return path }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        path.move(to: center)
        path.addArc(center: center, radius: min(rect.width, rect.height) / 2,
                    startAngle: .degrees(-90 + 360 * (1 - fraction)), endAngle: .degrees(270),
                    clockwise: false)
        path.closeSubpath()
        return path
    }
}
