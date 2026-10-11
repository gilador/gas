import AppKit
import SwiftUI
import UsageCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var viewModel: UsageViewModel?
    private var statusItemController: StatusItemController?
    private let panelController = DesktopPanelController()
    private var defaultsObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let viewModel = UsageViewModel()
        self.viewModel = viewModel
        UpdateModel.shared.start()
        panelController.viewModel = viewModel
        let setupModel = SetupModel(viewModel: viewModel)
        panelController.setupModel = setupModel
        statusItemController = StatusItemController(viewModel: viewModel) { [weak self] in
            self?.panelController.openSettings()
        } onSetup: { [weak self] in
            self?.panelController.openSetup()
        }
        Task {
            guard !UserDefaults.standard.bool(forKey: "setupShown") else { return }
            await viewModel.refresh()
            await setupModel.inspect()
            UserDefaults.standard.set(true, forKey: "setupShown")
            if setupModel.needsAttention { panelController.openSetup() }
        }
        viewModel.alerts.onFirstAlert = { [weak self] in self?.panelController.showForAlert() }
        viewModel.alerts.onAllAlertsEnded = { [weak self] in self?.panelController.hideAfterAlertIfUnpinned() }
        viewModel.alerts.onCritical = { [weak viewModel] crossings in
            // macOS notifications replace the dialog whenever the system allows them.
            guard viewModel?.notifications.permission != .allowed else { return }
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.alertStyle = .critical
                alert.messageText = "Critical gas limit reached"
                alert.informativeText = crossings.map { "\($0.provider.displayName) · \($0.limit.label) is at \($0.limit.displayPercent)%." }.joined(separator: "\n")
                alert.addButton(withTitle: "OK")
                NSApp.activate(ignoringOtherApps: true)
                alert.window.center()
                alert.runModal()
            }
        }
        applyPanelVisibility()
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.applyPanelVisibility() }
        }
    }

    private func applyPanelVisibility() {
        if UserDefaults.standard.bool(forKey: "showDesktopPanel") {
            panelController.show()
        } else {
            panelController.hide()
        }
    }
}
