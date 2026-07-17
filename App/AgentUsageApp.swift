import SwiftUI

@main
struct AgentUsageApp: App {
    var body: some Scene {
        MenuBarExtra("Agent Usage", systemImage: "gauge") {
            Text("Loading…")
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
        .menuBarExtraStyle(.window)
    }
}
