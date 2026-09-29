import AppKit
import SwiftUI

@MainActor
final class StatusItemController: NSObject {
    private static let autosaveName = "gas"
    private static let positionKey = "NSStatusItem Preferred Position \(autosaveName)"
    /// Points from the right edge; small values keep the item next to the clock when the bar is crowded.
    private static let defaultPosition = 120

    private let viewModel: UsageViewModel
    private let onSettings: () -> Void
    private let onSetup: () -> Void
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?

    init(viewModel: UsageViewModel, onSettings: @escaping () -> Void, onSetup: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onSettings = onSettings
        self.onSetup = onSetup
        super.init()
        if UserDefaults.standard.object(forKey: Self.positionKey) == nil {
            UserDefaults.standard.set(Self.defaultPosition, forKey: Self.positionKey)
        }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = Self.autosaveName
        item.behavior = [.removalAllowed]
        if let button = item.button {
            let host = NSHostingView(rootView: MenuBarLabelView(viewModel: viewModel))
            host.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(host)
            NSLayoutConstraint.activate([
                host.leadingAnchor.constraint(equalTo: button.leadingAnchor),
                host.trailingAnchor.constraint(equalTo: button.trailingAnchor),
                host.topAnchor.constraint(equalTo: button.topAnchor),
                host.bottomAnchor.constraint(equalTo: button.bottomAnchor)
            ])
            button.target = self
            button.action = #selector(togglePopover(_:))
        }
        statusItem = item
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem?.button else { return }
        if let popover, popover.isShown { popover.close(); return }
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MenuContentView(viewModel: viewModel, onSettings: onSettings, onSetup: onSetup))
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        DispatchQueue.main.async {
            NSApp.activate()
            popover.contentViewController?.view.window?.makeKeyAndOrderFront(nil)
        }
        self.popover = popover
    }
}
