import SwiftUI
import AppKit

@main
struct AgentUsageApp: App {
    @StateObject private var viewModel = UsageViewModel()
    @AppStorage("showDesktopPanel") private var showDesktopPanel = false
    @State private var panelController = DesktopPanelController()

    init() {
        let me = ProcessInfo.processInfo.processIdentifier
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        for other in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        where other.processIdentifier != me {
            other.terminate()
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(viewModel: viewModel, onSettings: { panelController.openSettings() })
        } label: {
            MenuBarLabelView(board: viewModel.board)
                .onAppear {
                    panelController.viewModel = viewModel
                    applyPanelVisibility()
                }
                .onChange(of: showDesktopPanel) { _, _ in
                    applyPanelVisibility()
                }
        }
        .menuBarExtraStyle(.window)
    }

    private func applyPanelVisibility() {
        if showDesktopPanel {
            panelController.show()
        } else {
            panelController.hide()
        }
    }
}
