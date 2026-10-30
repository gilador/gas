import SwiftUI
import UsageCore

struct DesktopPanelView: View {
    static let horizontalKey = "panelHorizontal"
    static let extendedKey = "panelExtended"
    /// The band along the top edge (right edge when horizontal) that holds the handle and flips the layout.
    private static let edgeThickness: CGFloat = 12

    @ObservedObject var viewModel: UsageViewModel
    @ObservedObject var alerts: AlertCenter
    @ObservedObject var pointer: PointerTracker
    @ObservedObject private var updates = UpdateModel.shared
    @AppStorage("panelTransparency") private var panelTransparency = 0.05
    @AppStorage(horizontalKey) private var horizontal = false
    @AppStorage(extendedKey) private var extended = false
    @AppStorage(ProviderSettings.key(.claude)) private var claudeEnabled = true
    @AppStorage(ProviderSettings.key(.openai)) private var openaiEnabled = true
    @AppStorage(ProviderSettings.key(.xai)) private var xaiEnabled = ProviderID.xai.isEnabledByDefault
    @State private var edgeFrame: CGRect = .zero
    let onTap: () -> Void
    let onDragStart: (CGSize) -> Void
    let onDragMove: () -> Void
    @State private var dragging = false

    var body: some View {
        let _ = (claudeEnabled, openaiEnabled, xaiEnabled)
        let layout = horizontal ? AnyLayout(HStackLayout(spacing: 6)) : AnyLayout(VStackLayout(spacing: 6))
        layout { content }
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
            .padding(horizontal ? EdgeInsets(top: 7, leading: 6, bottom: 7, trailing: 16)
                                : EdgeInsets(top: 10, leading: 4, bottom: 10, trailing: 4))
            .frame(width: horizontal ? nil : (extended ? 80 : 44), alignment: .topLeading)
            .modifier(PanelGlass(cornerRadius: 12))
            .contentShape(RoundedRectangle(cornerRadius: 12))
            // A few points of slack keep a still click a tap that opens the menu.
            .gesture(drag(minimumDistance: 3))
            .overlay(alignment: .topLeading) {
                if updates.showsDot {
                    Circle().fill(Color.accentColor).frame(width: 6, height: 6).padding(5)
                }
            }
            .overlay { edgeHighlight }
            .overlay(alignment: horizontal ? .trailing : .top) { edge }
            .onPreferenceChange(EdgeFrameKey.self) { edgeFrame = $0 }
            .opacity(1 - 0.9 * panelTransparency)
            .environment(\.colorScheme, .dark)
    }

    private var controlsVisible: Bool { pointer.location != nil }

    private var edge: some View {
        DragHandle(horizontal: horizontal, visible: controlsVisible)
            .frame(maxWidth: horizontal ? Self.edgeThickness : .infinity,
                   maxHeight: horizontal ? .infinity : Self.edgeThickness)
            .contentShape(Rectangle())
            .onTapGesture { horizontal.toggle() }
            .gesture(drag(minimumDistance: 3))
            .help(horizontal ? "Click for vertical layout" : "Click for horizontal layout")
            .background(GeometryReader { proxy in
                Color.clear.preference(key: EdgeFrameKey.self, value: proxy.frame(in: .global))
            })
    }

    /// Lights the glass border along the edge band while the pointer is on it.
    private var edgeHighlight: some View {
        RoundedRectangle(cornerRadius: 12)
            .strokeBorder(.white, lineWidth: 3)
            .mask(alignment: horizontal ? .trailing : .top) {
                Rectangle().frame(width: horizontal ? Self.edgeThickness : nil, height: horizontal ? nil : Self.edgeThickness)
            }
            .opacity(edgeHovered ? 0.8 : 0)
            .animation(.easeOut(duration: 0.15), value: edgeHovered)
            .allowsHitTesting(false)
    }

    private func drag(minimumDistance: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: minimumDistance, coordinateSpace: .global)
            .onChanged { value in
                if !dragging {
                    dragging = true
                    onDragStart(value.translation)
                }
                onDragMove()
            }
            .onEnded { _ in dragging = false }
    }

    /// SwiftUI hover is silent in this never-active app, so the tracked pointer decides.
    private var edgeHovered: Bool {
        guard let pointer = pointer.location, edgeFrame != .zero else { return false }
        return edgeFrame.contains(pointer)
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.board.isEmpty {
            Text("…").font(.caption).foregroundStyle(.secondary)
        } else {
            ForEach(Array(viewModel.visibleSnapshots.enumerated()), id: \.element.provider) { index, snapshot in
                if index > 0 {
                    Rectangle().fill(.white.opacity(0.15))
                        .frame(width: horizontal ? 1 : (extended ? 54 : 26), height: horizontal ? 26 : 1)
                }
                ProviderStripItem(snapshot: snapshot, alert: alerts.active[snapshot.provider], horizontal: horizontal,
                                  extended: extended)
            }
        }
    }
}

/// The pill on the edge band that shows the panel can move; shown while the pointer is inside.
private struct DragHandle: View {
    let horizontal: Bool
    let visible: Bool

    var body: some View {
        Capsule()
            .fill(.white)
            .frame(width: horizontal ? 5 : 16, height: horizontal ? 16 : 5)
            .opacity(visible ? 0.9 : 0)
            .animation(.easeOut(duration: 0.15), value: visible)
    }
}

/// Views that do not report still pass the default into reduce, so keep the one real value.
private struct EdgeFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}
