import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var viewModel: UsageViewModel?
    private var statusItemController: StatusItemController?
    private let panelController = DesktopPanelController()
    private var defaultsObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let viewModel = UsageViewModel()
        self.viewModel = viewModel
        panelController.viewModel = viewModel
        statusItemController = StatusItemController(viewModel: viewModel) { [weak self] in
            self?.panelController.openSettings()
        }
        viewModel.alerts.onFirstAlert = { [weak self] in self?.panelController.showForAlert() }
        viewModel.alerts.onAllAlertsEnded = { [weak self] in self?.panelController.hideAfterAlertIfUnpinned() }
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
