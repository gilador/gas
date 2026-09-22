import SwiftUI
import AppKit
import ServiceManagement
import UsageCore

struct PreferencesView: View {
    @ObservedObject var viewModel: UsageViewModel
    @ObservedObject var integration: ClaudeCodeIntegration
    @Environment(\.dismiss) private var dismiss

    @AppStorage("warningThreshold") private var warningThreshold = 80.0
    @AppStorage("criticalThreshold") private var criticalThreshold = 95.0
    @AppStorage("refreshInterval") private var refreshInterval = RefreshIntervals.defaultSeconds
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("Claude Code") {
                Toggle("Read usage from Claude Code", isOn: Binding(
                    get: { integration.isEnabled },
                    set: { integration.setEnabled($0) }))
                Text(integrationStatus)
                    .font(.caption).foregroundStyle(integrationIsFailed ? .red : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section("Notifications") {
                HStack {
                    Text("Warning %")
                    Slider(value: $warningThreshold, in: 15...100, step: 1)
                    Text("\(Int(warningThreshold))")
                }
                HStack {
                    Text("Critical %")
                    Slider(value: $criticalThreshold, in: 15...100, step: 1)
                    Text("\(Int(criticalThreshold))")
                }
            }
            Section {
                HStack {
                    Text("Refresh")
                    TickIntervalSlider(seconds: $refreshInterval, stopsSeconds: RefreshIntervals.stopsSeconds)
                    Text("\(Int((refreshInterval / 60).rounded())) min")
                        .monospacedDigit()
                        .frame(width: 52, alignment: .trailing)
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
        .onAppear { integration.refresh() }
        .padding(20)
        .formStyle(.grouped)
    }

    private var integrationStatus: String {
        switch integration.state {
        case .notConnected: return integration.isEnabled ? "Claude Code not found." : "Off. Claude usage comes from the Anthropic endpoint, which allows about one call per hour."
        case .connected(let lastUpdate?): return "Live. Updated \(lastUpdate.formatted(.relative(presentation: .named)))."
        case .connected(nil): return "Live after your next Claude Code session in a terminal."
        case .failed(let message): return "Failed: \(message)"
        }
    }
    private var integrationIsFailed: Bool { if case .failed = integration.state { return true }; return false }
}

/// An NSSlider with a tick mark per stop; snaps to ticks only.
struct TickIntervalSlider: NSViewRepresentable {
    @Binding var seconds: Double
    let stopsSeconds: [Double]

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSSlider {
        let slider = NSSlider(value: 0,
                              minValue: 0,
                              maxValue: Double(max(stopsSeconds.count - 1, 1)),
                              target: context.coordinator,
                              action: #selector(Coordinator.valueChanged(_:)))
        slider.numberOfTickMarks = stopsSeconds.count
        slider.allowsTickMarkValuesOnly = true
        slider.tickMarkPosition = .below
        slider.doubleValue = Double(index(for: seconds))
        return slider
    }

    func updateNSView(_ slider: NSSlider, context: Context) {
        context.coordinator.parent = self
        slider.doubleValue = Double(index(for: seconds))
    }

    private func index(for seconds: Double) -> Int {
        var best = 0
        var bestDiff = Double.greatestFiniteMagnitude
        for (i, value) in stopsSeconds.enumerated() {
            let diff = abs(value - seconds)
            if diff < bestDiff { bestDiff = diff; best = i }
        }
        return best
    }

    final class Coordinator: NSObject {
        var parent: TickIntervalSlider
        init(_ parent: TickIntervalSlider) { self.parent = parent }

        @objc func valueChanged(_ sender: NSSlider) {
            let idx = min(max(Int(sender.doubleValue.rounded()), 0), parent.stopsSeconds.count - 1)
            parent.seconds = parent.stopsSeconds[idx]
        }
    }
}
