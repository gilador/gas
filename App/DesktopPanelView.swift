import SwiftUI
import UsageCore

struct DesktopPanelView: View {
    static let horizontalKey = "panelHorizontal"
    static let extendedKey = "panelExtended"
    /// From the glass edge to the handle's center.
    private static let handleInset: CGFloat = 10

    /// The rotate arrow sits right after the handle (above it when horizontal).
    private static let rotateSize: CGFloat = 12

    @ObservedObject var viewModel: UsageViewModel
    @ObservedObject var alerts: AlertCenter
    @ObservedObject var pointer: PointerTracker
    @ObservedObject private var updates = UpdateModel.shared
    @AppStorage("panelTransparency") private var panelTransparency = 0.05
    @AppStorage(horizontalKey) private var horizontal = false
    @AppStorage(extendedKey) private var extended = false
    @AppStorage(ProviderSettings.key(.claude)) private var claudeEnabled = true
    @AppStorage(ProviderSettings.key(.openai)) private var openaiEnabled = true
    @State private var rotateFrame: CGRect = .zero
    let onTap: () -> Void
    let onDragStart: () -> Void
    let onDragMove: () -> Void
    @State private var dragging = false

    var body: some View {
        let _ = (claudeEnabled, openaiEnabled)
        let layout = horizontal ? AnyLayout(HStackLayout(spacing: 6)) : AnyLayout(VStackLayout(spacing: 6))
        layout { content }
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
            .padding(horizontal ? EdgeInsets(top: 7, leading: 6, bottom: 7, trailing: 16)
                                : EdgeInsets(top: 10, leading: 4, bottom: 10, trailing: 4))
            .frame(width: horizontal ? nil : 44, alignment: .topLeading)
            .modifier(PanelGlass(cornerRadius: 12))
            .overlay(alignment: .topLeading) {
                if updates.showsDot {
                    Circle().fill(Color.accentColor).frame(width: 6, height: 6).padding(5)
                }
            }
            .overlay(alignment: horizontal ? .trailing : .top) { handle }
            .onPreferenceChange(RotateFrameKey.self) { rotateFrame = $0 }
            .opacity(1 - 0.9 * panelTransparency)
            .environment(\.colorScheme, .dark)
    }

    private var controlsVisible: Bool { pointer.location != nil }

    private var handle: some View {
        DragHandle(horizontal: horizontal, visible: controlsVisible)
            .gesture(drag)
            .overlay(alignment: horizontal ? .top : .trailing) {
                rotate.offset(x: horizontal ? 0 : Self.rotateSize, y: horizontal ? -Self.rotateSize : 0)
            }
            .offset(x: horizontal ? DragHandle.hitThickness / 2 - Self.handleInset : 0,
                    y: horizontal ? 0 : Self.handleInset - DragHandle.hitThickness / 2)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { _ in
                if !dragging {
                    dragging = true
                    onDragStart()
                }
                onDragMove()
            }
            .onEnded { _ in dragging = false }
    }

    private var rotate: some View {
        RotateArrow()
            .stroke(.white, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            .frame(width: 9, height: 8)
            .opacity(rotateHovered ? 0.9 : 0)
            .frame(width: Self.rotateSize, height: Self.rotateSize)
            .contentShape(Rectangle())
            .onTapGesture { horizontal.toggle() }
            .help(horizontal ? "Vertical layout" : "Horizontal layout")
            .animation(.easeOut(duration: 0.15), value: rotateHovered)
            .background(GeometryReader { proxy in
                Color.clear.preference(key: RotateFrameKey.self, value: proxy.frame(in: .global))
            })
    }

    /// SwiftUI hover is silent in this never-active app, so the tracked pointer decides.
    private var rotateHovered: Bool {
        guard let pointer = pointer.location, rotateFrame != .zero else { return false }
        return rotateFrame.insetBy(dx: -2, dy: -2).contains(pointer)
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

/// The pill on the top edge (right edge when horizontal) that moves the panel; shown while the pointer is inside.
private struct DragHandle: View {
    static let hitThickness: CGFloat = 12

    let horizontal: Bool
    let visible: Bool

    var body: some View {
        Capsule()
            .fill(.white)
            .frame(width: horizontal ? 5 : 16, height: horizontal ? 16 : 5)
            .opacity(visible ? 0.9 : 0)
            .frame(width: horizontal ? Self.hitThickness : 18, height: horizontal ? 18 : Self.hitThickness)
            .contentShape(Rectangle())
            .help("Drag to move")
            .animation(.easeOut(duration: 0.15), value: visible)
    }
}

/// Views that do not report still pass the default into reduce, so keep the one real value.
private struct RotateFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

/// An arc over the top whose head points down on the right, like the corner of a turning card.
private struct RotateArrow: Shape {
    func path(in rect: CGRect) -> Path {
        let radius = rect.width / 2 - 1
        let center = CGPoint(x: rect.midX, y: rect.minY + radius + 1)
        let end = CGPoint(x: center.x + radius, y: center.y)
        let head = rect.width * 0.3
        var path = Path()
        path.addArc(center: center, radius: radius, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        path.move(to: CGPoint(x: end.x - head, y: end.y - head * 0.6))
        path.addLine(to: CGPoint(x: end.x, y: end.y + head * 0.4))
        path.addLine(to: CGPoint(x: end.x + head, y: end.y - head * 0.6))
        return path
    }
}
