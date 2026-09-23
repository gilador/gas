import SwiftUI
import AppKit
import ServiceManagement
import UsageCore

struct PreferencesView: View {
    @ObservedObject var viewModel: UsageViewModel
    @Environment(\.dismiss) private var dismiss

    @AppStorage("warningThreshold") private var warningThreshold = 65.0
    @AppStorage("criticalThreshold") private var criticalThreshold = 85.0
    @AppStorage("panelTransparency") private var panelTransparency = 0.05
    @AppStorage(UsageDisplayMode.key) private var usageDisplayRaw = UsageDisplayMode.used.rawValue
    @AppStorage(ProviderSettings.key(.claude)) private var claudeEnabled = true
    @AppStorage(ProviderSettings.key(.openai)) private var openaiEnabled = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("Display") {
                Picker("Show usage as", selection: $usageDisplayRaw) {
                    ForEach(UsageDisplayMode.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
            }
            Section("Providers") {
                ForEach(ProviderID.displayOrder, id: \.self) { provider in
                    Toggle(isOn: binding(for: provider)) {
                        HStack(spacing: 6) {
                            ProviderIcon(provider: provider, size: 14)
                            Text(provider.displayName)
                        }
                    }
                    .disabled(isOnlyEnabled(provider))
                }
            }
            Section("Notifications") {
                NotificationPermissionRow(notifications: viewModel.notifications)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Warning %")
                        Spacer()
                        Text("\(Int(warningThreshold))").monospacedDigit()
                    }
                    Slider(value: Binding(get: { warningThreshold }, set: { warningThreshold = $0.rounded() }), in: 15...100)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Critical %")
                        Spacer()
                        Text("\(Int(criticalThreshold))").monospacedDigit()
                    }
                    Slider(value: Binding(get: { criticalThreshold }, set: { criticalThreshold = $0.rounded() }), in: 15...100)
                }
            }
            Section("Floating panel") {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Transparency")
                        Spacer()
                        Text("\(Int((panelTransparency * 100).rounded()))%").monospacedDigit()
                    }
                    Slider(value: Binding(get: { 1 - panelTransparency },
                                          set: { panelTransparency = ((1 - $0) * 20).rounded() / 20 }), in: 0...1)
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
                dismiss()
            }
        }
        .padding(20)
        .formStyle(.grouped)
    }

    private func binding(for provider: ProviderID) -> Binding<Bool> {
        switch provider {
        case .claude: return Binding(get: { claudeEnabled }, set: { claudeEnabled = $0; providersChanged(to: $0) })
        case .openai: return Binding(get: { openaiEnabled }, set: { openaiEnabled = $0; providersChanged(to: $0) })
        case .xai: return .constant(false)
        }
    }

    private func isOnlyEnabled(_ provider: ProviderID) -> Bool {
        ProviderSettings.enabled() == [provider]
    }

    private func providersChanged(to enabled: Bool) {
        if enabled { Task { await viewModel.refresh(manual: true) } }
    }
}

private struct NotificationPermissionRow: View {
    @ObservedObject var notifications: NotificationManager

    var body: some View {
        HStack {
            Text(text).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            if notifications.permission == .denied || notifications.permission == .notDetermined {
                Button("Open Notification Settings") { notifications.openSystemSettings() }
            }
        }
        .task { await notifications.refreshPermission() }
    }

    private var text: String {
        switch notifications.permission {
        case .allowed: return "macOS notifications are on for gas."
        case .notDetermined: return "gas has not been allowed to notify yet."
        case .denied: return "macOS notifications are off for gas."
        case .unavailable: return "Notifications need a team-signed build. Critical alerts show as a dialog."
        case .blockedBySigning: return "macOS only lets Developer ID signed apps notify. Critical alerts show as a dialog until then."
        }
    }
}
