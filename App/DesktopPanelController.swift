import AppKit
import SwiftUI

@MainActor
final class DesktopPanelController {
    var viewModel: UsageViewModel?

    private var panel: NSPanel?
    private var moveObserver: NSObjectProtocol?
    private static let size = NSSize(width: 220, height: 120)
    // nonisolated: immutable Sendable constants referenced from the @Sendable didMove observer closure.
    nonisolated private static let originXKey = "desktopPanelOriginX"
    nonisolated private static let originYKey = "desktopPanelOriginY"

    func show() {
        guard let viewModel else { return }
        if panel == nil { panel = makePanel(viewModel: viewModel) }
        guard let panel else { return }
        positionPanel(panel)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel(viewModel: UsageViewModel) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)))
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = false

        let host = NSHostingView(rootView: DesktopPanelView(viewModel: viewModel))
        host.frame = NSRect(origin: .zero, size: Self.size)
        panel.contentView = host

        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: panel, queue: .main) { note in
            guard let moved = note.object as? NSWindow else { return }
            let origin = moved.frame.origin
            UserDefaults.standard.set(Double(origin.x), forKey: Self.originXKey)
            UserDefaults.standard.set(Double(origin.y), forKey: Self.originYKey)
        }
        return panel
    }

    private func positionPanel(_ panel: NSPanel) {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Self.originXKey) != nil,
           defaults.object(forKey: Self.originYKey) != nil {
            let origin = NSPoint(x: defaults.double(forKey: Self.originXKey),
                                 y: defaults.double(forKey: Self.originYKey))
            panel.setFrameOrigin(clampedOrigin(origin))
        } else {
            panel.setFrameOrigin(defaultOrigin())
        }
    }

    private func clampedOrigin(_ origin: NSPoint) -> NSPoint {
        let rect = NSRect(origin: origin, size: Self.size)
        if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(rect) }) {
            return origin
        }
        return defaultOrigin()
    }

    private func defaultOrigin() -> NSPoint {
        guard let vf = NSScreen.main?.visibleFrame else { return .zero }
        return NSPoint(x: vf.maxX - Self.size.width - 20,
                       y: vf.maxY - Self.size.height - 20)
    }
}
