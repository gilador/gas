import AppKit
import SwiftUI

@MainActor
final class DesktopPanelController {
    var viewModel: UsageViewModel?
    var setupModel: SetupModel?

    private var panel: NSPanel?
    private var moveObserver: NSObjectProtocol?
    private var resizeObserver: NSObjectProtocol?
    private var topRight: NSPoint?
    private var settingsWindow: NSWindow?
    private var setupWindow: NSWindow?
    private var setupCloseObserver: NSObjectProtocol?
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
            rootView: MenuContentView(viewModel: viewModel,
                                      onSettings: { [weak self] in self?.openSettings() },
                                      onSetup: { [weak self] in self?.openSetup() }))
        NSApp.activate()
        let horizontal = UserDefaults.standard.bool(forKey: DesktopPanelView.horizontalKey)
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: horizontal ? .minY : .minX)
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
            let hosting = NSHostingController(rootView: PreferencesView(viewModel: viewModel,
                                                                       onSetup: { [weak self] in self?.openSetup() }))
            hosting.sizingOptions = []
            let window = NSWindow(contentViewController: hosting)
            window.title = "Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 380, height: 640))
            window.center()
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        settingsWindow?.orderFrontRegardless()
    }

    func openSetup() {
        guard let setupModel else { return }
        NSApp.activate(ignoringOtherApps: true)
        if setupWindow == nil {
            let hosting = NSHostingController(rootView: SetupView(model: setupModel, onDone: { [weak self] in
                self?.setupWindow?.close()
            }))
            hosting.sizingOptions = []
            let window = NSWindow(contentViewController: hosting)
            window.title = "Set up providers"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 500, height: 340))
            window.center()
            setupCloseObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak setupModel] _ in
                MainActor.assumeIsolated { setupModel?.cancel() }
            }
            setupWindow = window
        }
        setupWindow?.makeKeyAndOrderFront(nil)
        setupWindow?.orderFrontRegardless()
        Task { await setupModel.inspect() }
    }

    private func makePanel(viewModel: UsageViewModel) -> NSPanel {
        let panel = GlassPanel(
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

        let pointer = PointerTracker()
        let host = TrackingHostingView(rootView: DesktopPanelView(viewModel: viewModel, alerts: viewModel.alerts, pointer: pointer,
                                                                  onTap: { [weak self] in self?.toggleMenu() }))
        host.tracker = pointer
        host.sizingOptions = [.preferredContentSize]
        panel.acceptsMouseMovedEvents = true
        panel.contentView = host

        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: panel, queue: .main) { [weak self] note in
            guard let moved = note.object as? NSWindow else { return }
            let origin = moved.frame.origin
            UserDefaults.standard.set(Double(origin.x), forKey: Self.originXKey)
            UserDefaults.standard.set(Double(origin.y), forKey: Self.originYKey)
            let topRight = NSPoint(x: moved.frame.maxX, y: moved.frame.maxY)
            MainActor.assumeIsolated { self?.topRight = topRight }
        }
        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.keepTopRight() }
        }
        return panel
    }

    /// AppKit keeps the bottom-left corner when the content changes size; a layout flip keeps the top-right one,
    /// where the flip pill sits in both layouts, so the pointer stays on it.
    private func keepTopRight() {
        guard let panel, let topRight else { return }
        var frame = panel.frame
        frame.origin = NSPoint(x: topRight.x - frame.width, y: topRight.y - frame.height)
        if let visible = (panel.screen ?? NSScreen.main)?.visibleFrame {
            frame.origin = Self.fitted(frame.origin, size: frame.size, in: visible)
        }
        if frame.origin != panel.frame.origin { panel.setFrameOrigin(frame.origin) }
    }

    private static func fitted(_ origin: NSPoint, size: NSSize, in visible: NSRect) -> NSPoint {
        NSPoint(x: min(max(origin.x, visible.minX), visible.maxX - size.width),
                y: min(max(origin.y, visible.minY), visible.maxY - size.height))
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
        if let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(rect) }) {
            return Self.fitted(origin, size: size, in: screen.visibleFrame)
        }
        return defaultOrigin(size: size)
    }

    private func defaultOrigin(size: NSSize) -> NSPoint {
        guard let vf = NSScreen.main?.visibleFrame else { return .zero }
        return NSPoint(x: vf.maxX - size.width - 20,
                       y: vf.maxY - size.height - 20)
    }
}

/// Liquid Glass freezes its backdrop in windows that are not key; this display-only panel
/// reports itself key and main so the glass keeps sampling what is behind it.
final class GlassPanel: NSPanel {
    override var isKeyWindow: Bool { true }
    override var isMainWindow: Bool { true }
}
