import SwiftUI
import UsageCore

struct DesktopPanelView: View {
    static let horizontalKey = "panelHorizontal"

    @ObservedObject var viewModel: UsageViewModel
    @ObservedObject var alerts: AlertCenter
    @AppStorage("panelTransparency") private var panelTransparency = 0.05
    @AppStorage(horizontalKey) private var horizontal = false
    @AppStorage(ProviderSettings.key(.claude)) private var claudeEnabled = true
    @AppStorage(ProviderSettings.key(.openai)) private var openaiEnabled = true
    let onTap: () -> Void

    var body: some View {
        let _ = (claudeEnabled, openaiEnabled)
        let layout = horizontal ? AnyLayout(HStackLayout(spacing: 6)) : AnyLayout(VStackLayout(spacing: 6))
        layout {
            if !horizontal { toggle }
            content
            if horizontal { toggle }
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .padding(horizontal ? EdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 2)
                            : EdgeInsets(top: 2, leading: 4, bottom: 10, trailing: 4))
        .frame(width: horizontal ? nil : 44, height: horizontal ? 44 : nil, alignment: .topLeading)
        .modifier(PanelGlass(cornerRadius: 12))
        .opacity(1 - 0.9 * panelTransparency)
        .environment(\.colorScheme, .dark)
    }

    private var toggle: some View {
        LayoutToggle(horizontal: horizontal) { horizontal.toggle() }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.board.isEmpty {
            Text("…").font(.caption).foregroundStyle(.secondary)
        } else {
            ForEach(Array(viewModel.visibleSnapshots.enumerated()), id: \.element.provider) { index, snapshot in
                if index > 0 {
                    Rectangle().fill(.white.opacity(0.15))
                        .frame(width: horizontal ? 1 : 26, height: horizontal ? 26 : 1)
                }
                ProviderStripItem(snapshot: snapshot, alert: alerts.active[snapshot.provider], horizontal: horizontal)
            }
        }
    }
}

/// Hidden until the pointer is over it: a pill on the top edge (right edge when horizontal) that flips the layout.
private struct LayoutToggle: View {
    let horizontal: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Capsule()
            .fill(.white)
            .frame(width: horizontal ? 5 : 30, height: horizontal ? 30 : 5)
            .opacity(hovering ? 0.9 : 0)
            .frame(width: horizontal ? 12 : 36, height: horizontal ? 32 : 12)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .onTapGesture(perform: action)
            .help(horizontal ? "Vertical layout" : "Horizontal layout")
            .animation(.easeOut(duration: 0.15), value: hovering)
    }
}
