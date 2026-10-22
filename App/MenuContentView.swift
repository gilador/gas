import SwiftUI
import UsageCore

struct MenuContentView: View {
    @ObservedObject var viewModel: UsageViewModel
    let onSettings: () -> Void
    let onSetup: () -> Void
    @ObservedObject private var updates = UpdateModel.shared
    @State private var hoversRefresh = false
    @AppStorage("showDesktopPanel") private var showDesktopPanel = true
    @AppStorage(ProviderSettings.key(.claude)) private var claudeEnabled = true
    @AppStorage(ProviderSettings.key(.openai)) private var openaiEnabled = true

    var body: some View {
        let _ = (claudeEnabled, openaiEnabled)
        VStack(alignment: .leading, spacing: 8) {
            Text("g · a · s")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
            if updates.showsDot {
                Divider()
                UpdateBanner(updates: updates)
            }
            Divider()
            if viewModel.board.isEmpty {
                Text("Loading…")
            } else {
                ForEach(Array(viewModel.visibleSnapshots.enumerated()), id: \.element.provider) { index, snapshot in
                    if index > 0 { Divider() }
                    ProviderSection(snapshot: snapshot,
                                    onRetry: { Task { await viewModel.refresh(manual: true) } },
                                    onSetup: onSetup)
                }
                if let updated = viewModel.board.latestFetchedAt {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(footer(updated: updated, now: context.date))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Divider()
            HStack(spacing: 14) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let waiting = viewModel.manualDebounceEnd(now: context.date) != nil
                    Button { Task { await viewModel.refresh(manual: true) } } label: {
                        Image(systemName: "arrow.clockwise")
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .disabled(waiting)
                    .help(waiting ? "" : "Refresh now")
                    // A disabled button gets no hover, so a clear layer on top reads it while the button can't be clicked anyway.
                    .overlay {
                        if waiting {
                            Color.clear.contentShape(Rectangle()).onHover { hoversRefresh = $0 }
                        }
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if hoversRefresh {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            if let end = viewModel.manualDebounceEnd(now: context.date) {
                                HoverHint(text: waitText(until: end, now: context.date))
                            }
                        }
                        .offset(y: -28)
                    }
                }

                Button(action: onSettings) {
                    Image(systemName: "gearshape")
                        .overlay(alignment: .topTrailing) {
                            if updates.showsDot {
                                Circle().fill(Color.accentColor).frame(width: 5, height: 5).offset(x: 2, y: -2)
                            }
                        }
                }
                .buttonStyle(.plain)
                .help("Preferences")

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

    /// One shared timer refreshes every provider, so the soonest refresh is the one shown.
    private func footer(updated: Date, now: Date) -> String {
        let updatedText = "Updated \(RelativeAge.compact(from: updated, now: now))"
        guard let next = viewModel.visibleSnapshots.map({ viewModel.nextRefresh(for: $0.provider) }).min() else { return updatedText }
        return "\(updatedText) · Next refresh \(RefreshCountdown.text(until: next, now: now))"
    }

    private func waitText(until end: Date, now: Date) -> String {
        let seconds = max(1, Int(end.timeIntervalSince(now).rounded(.up)))
        return "Try again in \(seconds) second\(seconds == 1 ? "" : "s")"
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
    @AppStorage(UsageDisplayMode.key) private var usageDisplayRaw = UsageDisplayMode.remaining.rawValue
    private var mode: UsageDisplayMode { .current(usageDisplayRaw) }
    @State private var showsTimeLeft = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(limit.label).font(.callout)
                Spacer()
                Text("\(mode.percent(for: limit))%" + (mode == .remaining ? " left" : "")).font(.callout.monospacedDigit())
            }
            LimitBar(fraction: mode.fraction(for: limit), color: LimitPalette.color(for: limit))
            if let reset = limit.resetsAt {
                HStack(spacing: 3) {
                    TimelineView(.everyMinute) { context in
                        Text("Resets \(ResetTime.text(for: reset, now: context.date))")
                    }
                    Image(systemName: "info.circle")
                        .contentShape(Rectangle())
                        .onHover { showsTimeLeft = $0 }
                }
                .font(.caption2).foregroundStyle(.secondary)
                .overlay(alignment: .bottomLeading) {
                    if showsTimeLeft {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            HoverHint(text: ResetTime.remaining(until: reset, now: context.date))
                        }
                        .offset(y: -18)
                    }
                }
            }
        }
    }
}

/// A hint drawn inside the menu: a popover is its own window, and opening it ends the hover that showed it.
struct HoverHint: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.white.opacity(0.15)))
            .fixedSize()
            .allowsHitTesting(false)
    }
}
