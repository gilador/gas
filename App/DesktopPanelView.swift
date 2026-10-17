import SwiftUI
import UsageCore

struct DesktopPanelView: View {
    static let horizontalKey = "panelHorizontal"
    static let extendedKey = "panelExtended"
    /// The flip pill shows once the pointer is this close to its hit area: about 10 pt past a "0%" label.
    private static let revealMargin: CGFloat = 14
    /// From the glass edge to the pill's center.
    private static let pillInset: CGFloat = 10

    @ObservedObject var viewModel: UsageViewModel
    @ObservedObject var alerts: AlertCenter
    @ObservedObject var pointer: PointerTracker
    @ObservedObject private var updates = UpdateModel.shared
    @AppStorage("panelTransparency") private var panelTransparency = 0.05
    @AppStorage(horizontalKey) private var horizontal = false
    @AppStorage(extendedKey) private var extended = false
    @AppStorage(ProviderSettings.key(.claude)) private var claudeEnabled = true
    @AppStorage(ProviderSettings.key(.openai)) private var openaiEnabled = true
    let onTap: () -> Void
    let onDragStart: () -> Void
    let onDragMove: () -> Void
    @State private var toggleFrame: CGRect = .zero
    @State private var pressing = false
    @State private var dragging = false

    var body: some View {
        let _ = (claudeEnabled, openaiEnabled)
        let layout = horizontal ? AnyLayout(HStackLayout(spacing: 6)) : AnyLayout(VStackLayout(spacing: 6))
        layout { content }
            .contentShape(Rectangle())
            .gesture(tapOrDrag)
            .padding(horizontal ? EdgeInsets(top: 7, leading: 6, bottom: 7, trailing: 16)
                                : EdgeInsets(top: 10, leading: 4, bottom: 10, trailing: 4))
            .frame(width: horizontal ? nil : 44, alignment: .topLeading)
            .modifier(PanelGlass(cornerRadius: 12))
            .overlay(alignment: .topLeading) {
                if updates.showsDot {
                    Circle().fill(Color.accentColor).frame(width: 6, height: 6).padding(5)
                }
            }
            .overlay(alignment: horizontal ? .trailing : .top) { toggle }
            .onPreferenceChange(ToggleFrameKey.self) { toggleFrame = $0 }
            .opacity(1 - 0.9 * panelTransparency)
            .environment(\.colorScheme, .dark)
    }

    /// The strip-wide tap takes the mouse-down from AppKit's drag-by-background, so the strip moves the window itself.
    private var tapOrDrag: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                if !pressing {
                    pressing = true
                    onDragStart()
                }
                if dragging || hypot(value.translation.width, value.translation.height) > 3 {
                    dragging = true
                    onDragMove()
                }
            }
            .onEnded { _ in
                if !dragging { onTap() }
                pressing = false
                dragging = false
            }
    }

    private var toggle: some View {
        LayoutToggle(horizontal: horizontal, visible: toggleVisible) { horizontal.toggle() }
            .background(GeometryReader { proxy in
                Color.clear.preference(key: ToggleFrameKey.self, value: proxy.frame(in: .global))
            })
            .offset(x: horizontal ? LayoutToggle.hitThickness / 2 - Self.pillInset : 0,
                    y: horizontal ? 0 : Self.pillInset - LayoutToggle.hitThickness / 2)
    }

    private var toggleVisible: Bool {
        guard let pointer = pointer.location, toggleFrame != .zero else { return false }
        let dx = max(toggleFrame.minX - pointer.x, 0, pointer.x - toggleFrame.maxX)
        let dy = max(toggleFrame.minY - pointer.y, 0, pointer.y - toggleFrame.maxY)
        return hypot(dx, dy) <= Self.revealMargin
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
                ProviderStripItem(snapshot: snapshot, alert: alerts.active[snapshot.provider], horizontal: horizontal,
                                  extended: extended)
            }
        }
    }
}

/// A pill near the top edge (right edge when horizontal) that flips the layout; hidden until the pointer is near.
private struct LayoutToggle: View {
    static let hitThickness: CGFloat = 12

    let horizontal: Bool
    let visible: Bool
    let action: () -> Void

    var body: some View {
        Capsule()
            .fill(.white)
            .frame(width: horizontal ? 5 : 30, height: horizontal ? 24 : 5)
            .opacity(visible ? 0.9 : 0)
            .frame(width: horizontal ? Self.hitThickness : 36, height: horizontal ? 26 : Self.hitThickness)
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
            .help(horizontal ? "Vertical layout" : "Horizontal layout")
            .animation(.easeOut(duration: 0.15), value: visible)
    }
}

/// Views that do not report still pass the default into reduce, so keep the one real value.
private struct ToggleFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}
