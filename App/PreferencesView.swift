import SwiftUI
import AppKit
import ServiceManagement
import UsageCore

struct PreferencesView: View {
    @ObservedObject var viewModel: UsageViewModel
    @Environment(\.dismiss) private var dismiss

    @AppStorage("warningThreshold") private var warningThreshold = 80.0
    @AppStorage("criticalThreshold") private var criticalThreshold = 95.0
    @AppStorage("refreshInterval") private var refreshInterval = RefreshIntervals.defaultSeconds
    @AppStorage("panelTransparency") private var panelTransparency = 0.0
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("Notifications") {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Warning %")
                        Spacer()
                        Text("\(Int(warningThreshold))").monospacedDigit()
                    }
                    Slider(value: $warningThreshold, in: 15...100, step: 1)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Critical %")
                        Spacer()
                        Text("\(Int(criticalThreshold))").monospacedDigit()
                    }
                    Slider(value: $criticalThreshold, in: 15...100, step: 1)
                }
            }
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Refresh")
                        Spacer()
                        Text("\(Int((refreshInterval / 60).rounded())) min").monospacedDigit()
                    }
                    TickIntervalSlider(seconds: $refreshInterval, stopsSeconds: RefreshIntervals.stopsSeconds)
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
                                          set: { panelTransparency = 1 - $0 }), in: 0...1, step: 0.05)
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
        .formStyle(.grouped)
    }
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
