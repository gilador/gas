import SwiftUI

@main
struct AgentUsageApp: App {
    @StateObject private var viewModel = UsageViewModel()
    @AppStorage("showDesktopPanel") private var showDesktopPanel = false
    @State private var panelController = DesktopPanelController()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(viewModel: viewModel)
        } label: {
            MenuBarLabelView(snapshot: viewModel.snapshot)
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
