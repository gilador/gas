import SwiftUI
import UsageCore

struct DesktopPanelView: View {
    @ObservedObject var viewModel: UsageViewModel
    @ObservedObject var alerts: AlertCenter
    @AppStorage("panelTransparency") private var panelTransparency = 0.05
    @AppStorage(ProviderSettings.key(.claude)) private var claudeEnabled = true
    @AppStorage(ProviderSettings.key(.openai)) private var openaiEnabled = true
    let onTap: () -> Void

    var body: some View {
        let _ = (claudeEnabled, openaiEnabled)
        VStack(spacing: 6) {
            content
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .padding(.horizontal, 4)
        .padding(.vertical, 10)
        .frame(width: 44, alignment: .top)
        .modifier(PanelGlass(cornerRadius: 12))
        .opacity(1 - 0.9 * panelTransparency)
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.board.isEmpty {
            Text("…").font(.caption).foregroundStyle(.secondary)
        } else {
            ForEach(Array(viewModel.visibleSnapshots.enumerated()), id: \.element.provider) { index, snapshot in
                if index > 0 {
                    Rectangle().fill(.white.opacity(0.15)).frame(width: 26, height: 1)
                }
                ProviderStripItem(snapshot: snapshot, alert: alerts.active[snapshot.provider])
            }
        }
    }
}
