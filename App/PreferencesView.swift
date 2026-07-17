import SwiftUI
import ServiceManagement
import UsageCore

struct PreferencesView: View {
    @ObservedObject var viewModel: UsageViewModel
    @Environment(\.dismiss) private var dismiss

    @AppStorage("warningThreshold") private var warningThreshold = 80.0
    @AppStorage("criticalThreshold") private var criticalThreshold = 95.0
    @AppStorage("refreshInterval") private var refreshInterval = 60.0
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("Notifications") {
                HStack {
                    Text("Warning %")
                    Slider(value: $warningThreshold, in: 50...100, step: 1)
                    Text("\(Int(warningThreshold))")
                }
                HStack {
                    Text("Critical %")
                    Slider(value: $criticalThreshold, in: 50...100, step: 1)
                    Text("\(Int(criticalThreshold))")
                }
            }
            Section("Refresh") {
                HStack {
                    Text("Interval (s)")
                    Slider(value: $refreshInterval, in: 30...300, step: 10)
                    Text("\(Int(refreshInterval))")
                }
            }
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        try? (enabled ? SMAppService.mainApp.register()
                                      : SMAppService.mainApp.unregister())
                    }
            }
            Button("Done") {
                viewModel.refreshInterval = refreshInterval
                viewModel.start()
                dismiss()
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}
