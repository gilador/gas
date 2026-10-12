import SwiftUI
import AppKit
import ServiceManagement
import UsageCore

struct PreferencesView: View {
    @ObservedObject var viewModel: UsageViewModel
    let onSetup: () -> Void
    @Environment(\.dismiss) private var dismiss

    @AppStorage("warningThreshold") private var warningThreshold = 65.0
    @AppStorage("criticalThreshold") private var criticalThreshold = 85.0
    @AppStorage("panelTransparency") private var panelTransparency = 0.05
    @AppStorage(UsageDisplayMode.key) private var usageDisplayRaw = UsageDisplayMode.used.rawValue
    @AppStorage(ProviderSettings.key(.claude)) private var claudeEnabled = true
    @AppStorage(ProviderSettings.key(.openai)) private var openaiEnabled = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var copiedDiagnostics = false
    @AppStorage(UpdateModel.autoCheckKey) private var checkForUpdates = true
    @ObservedObject private var updates = UpdateModel.shared
    @AppStorage(ProviderSettings.renewClaudeTokenKey) private var renewClaudeToken = true

    var body: some View {
        Form {
            Section("Updates") {
                Toggle("Check for updates automatically", isOn: $checkForUpdates)
                HStack {
                    Button("Check for updates") { Task { await updates.check(manual: true) } }
                        .disabled(updates.phase == .checking)
                    Spacer()
                    if case .available = updates.phase {
                        Button("Update available") { Task { await updates.update() } }
                            .buttonStyle(.borderedProminent)
                    } else {
                        Text(updateStatus).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
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
                Toggle("Renew Claude token automatically", isOn: $renewClaudeToken)
                    .disabled(!claudeEnabled)
                    .help("When the token expires or the server rejects it, gas runs Claude Code once in the background (one short Haiku reply) so it renews its token, or finds that it is logged out.")
                Button("Set up providers…", action: onSetup)
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
            Section("Troubleshooting") {
                Button(copiedDiagnostics ? "Copied — paste it into a message" : "Copy diagnostics", action: copyDiagnostics)
            }
            Button("Done") {
                dismiss()
            }
        }
        .padding(20)
        .formStyle(.grouped)
    }

    private var updateStatus: String {
        let installed = updates.installed?.description ?? "?"
        switch updates.phase {
        case .idle: return "Version \(installed)"
        case .checking: return "Checking…"
        case .upToDate: return "Up to date (\(installed))"
        case .checkFailed(let message): return "Couldn't check: \(message)"
        case .available(let release): return "gas \(release.version.description) is available"
        case .downloading: return "Downloading…"
        case .failed(_, let message): return "Update failed: \(message)"
        }
    }

    private func copyDiagnostics() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(viewModel.diagnosticsReport(), forType: .string)
        copiedDiagnostics = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { copiedDiagnostics = false }
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
