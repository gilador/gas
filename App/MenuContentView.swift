import SwiftUI
import UsageCore

struct MenuContentView: View {
    @ObservedObject var viewModel: UsageViewModel
    let onSettings: () -> Void
    @AppStorage("showDesktopPanel") private var showDesktopPanel = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if viewModel.board.isEmpty {
                Text("Loading…")
            } else {
                ForEach(Array(viewModel.board.snapshots.enumerated()), id: \.element.provider) { index, snapshot in
                    if index > 0 { Divider() }
                    ProviderSection(snapshot: snapshot)
                }
                if let updated = viewModel.board.latestFetchedAt {
                    (Text("Updated ") + Text(updated, style: .relative) + Text(" ago"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Divider()
            HStack(spacing: 14) {
                Button { Task { await viewModel.refresh() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Refresh now")

                Button(action: onSettings) {
                    Image(systemName: "gearshape")
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

    private func confirmQuit() {
        let alert = NSAlert()
        alert.messageText = "Quit Tokens?"
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

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(limit.label).font(.callout)
                Spacer()
                Text("\(Int(limit.percentUsed.rounded()))%").font(.callout.monospacedDigit())
            }
            LimitBar(fraction: limit.percentUsed / 100, color: LimitPalette.color(for: limit))
            if let reset = limit.resetsAt {
                Text("Resets \(reset.formatted(.relative(presentation: .named)))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
