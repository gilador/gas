import SwiftUI

@main
struct AgentUsageApp: App {
    @StateObject private var viewModel = UsageViewModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(viewModel: viewModel)
        } label: {
            MenuBarLabelView(snapshot: viewModel.snapshot)
        }
        .menuBarExtraStyle(.window)
    }
}
