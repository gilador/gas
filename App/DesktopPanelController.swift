import AppKit
import SwiftUI

@MainActor
final class DesktopPanelController {
    var viewModel: UsageViewModel?

    private var panel: NSPanel?
    private var moveObserver: NSObjectProtocol?
    private var settingsWindow: NSWindow?
    private var menuPopover: NSPopover?
    private static let size = NSSize(width: 44, height: 280)
    // nonisolated: immutable Sendable constants referenced from the @Sendable didMove observer closure.
    nonisolated private static let originXKey = "desktopPanelOriginX"
    nonisolated private static let originYKey = "desktopPanelOriginY"

    func show() {
        if panel?.isVisible == true {
            panel?.orderFrontRegardless()
            return
        }
        guard let viewModel else { return }
        if panel == nil { panel = makePanel(viewModel: viewModel) }
        guard let panel else { return }
        panel.level = .floating   // re-assert always-on-top each time it's shown
        panel.layoutIfNeeded()
        positionPanel(panel)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func showForAlert() {
        show()
    }

    func hideAfterAlertIfUnpinned() {
        if !UserDefaults.standard.bool(forKey: "showDesktopPanel") { hide() }
    }

    /// The same dropdown as the menu bar item, anchored to the strip.
    func toggleMenu() {
        guard let viewModel, let panel, let anchor = panel.contentView else { return }
        if let menuPopover, menuPopover.isShown { menuPopover.close(); return }
        let popover = NSPopover()
        popover.behavior = .transient
        popover.appearance = NSAppearance(named: .darkAqua)
        popover.contentViewController = NSHostingController(
            rootView: MenuContentView(viewModel: viewModel, onSettings: { [weak self] in self?.openSettings() }))
        NSApp.activate()
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minX)
        DispatchQueue.main.async {
            NSApp.activate()
            popover.contentViewController?.view.window?.makeKeyAndOrderFront(nil)
        }
        menuPopover = popover
    }

    func openSettings() {
        guard let viewModel else { return }
        NSApp.activate(ignoringOtherApps: true)
        if settingsWindow == nil {
            let hosting = NSHostingController(rootView: PreferencesView(viewModel: viewModel))
            hosting.sizingOptions = []
            let window = NSWindow(contentViewController: hosting)
            window.title = "Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 380, height: 520))
            window.center()
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        settingsWindow?.orderFrontRegardless()
    }

    private func makePanel(viewModel: UsageViewModel) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        panel.level = .floating   // always on top of normal windows
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = false

        let host = NSHostingView(rootView: DesktopPanelView(viewModel: viewModel, alerts: viewModel.alerts, onTap: { [weak self] in self?.toggleMenu() }))
        host.sizingOptions = [.preferredContentSize]
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
        let size = panel.frame.size
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Self.originXKey) != nil,
           defaults.object(forKey: Self.originYKey) != nil {
            let origin = NSPoint(x: defaults.double(forKey: Self.originXKey),
                                 y: defaults.double(forKey: Self.originYKey))
            panel.setFrameOrigin(clampedOrigin(origin, size: size))
        } else {
            panel.setFrameOrigin(defaultOrigin(size: size))
        }
    }

    private func clampedOrigin(_ origin: NSPoint, size: NSSize) -> NSPoint {
        let rect = NSRect(origin: origin, size: size)
        if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(rect) }) {
            return origin
        }
        return defaultOrigin(size: size)
    }

    private func defaultOrigin(size: NSSize) -> NSPoint {
        guard let vf = NSScreen.main?.visibleFrame else { return .zero }
        return NSPoint(x: vf.maxX - size.width - 20,
                       y: vf.maxY - size.height - 20)
    }
}
