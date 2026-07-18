import SwiftUI
import AppKit
import ServiceManagement
import UsageCore

struct PreferencesView: View {
    @ObservedObject var viewModel: UsageViewModel
    @Environment(\.dismiss) private var dismiss

    @AppStorage("warningThreshold") private var warningThreshold = 80.0
    @AppStorage("criticalThreshold") private var criticalThreshold = 95.0
    @AppStorage("refreshInterval") private var refreshInterval = 780.0   // default 13 min
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    /// Fibonacci-minute refresh stops, stored/used as seconds.
    private static let fibSeconds = [1, 2, 3, 5, 8, 13, 21, 34, 55].map { $0 * 60 }

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
            Section {
                HStack {
                    Text("Refresh")
                    FibonacciIntervalSlider(seconds: $refreshInterval, fibSeconds: Self.fibSeconds)
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
        .padding(20)
        .frame(width: 360)
    }
}

/// An NSSlider with tick marks at each Fibonacci-minute stop; snaps to ticks only.
struct FibonacciIntervalSlider: NSViewRepresentable {
    @Binding var seconds: Double
    let fibSeconds: [Int]

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSSlider {
        let slider = NSSlider(value: 0,
                              minValue: 0,
                              maxValue: Double(max(fibSeconds.count - 1, 1)),
                              target: context.coordinator,
                              action: #selector(Coordinator.valueChanged(_:)))
        slider.numberOfTickMarks = fibSeconds.count
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
        for (i, value) in fibSeconds.enumerated() {
            let diff = abs(Double(value) - seconds)
            if diff < bestDiff { bestDiff = diff; best = i }
        }
        return best
    }

    final class Coordinator: NSObject {
        var parent: FibonacciIntervalSlider
        init(_ parent: FibonacciIntervalSlider) { self.parent = parent }

        @objc func valueChanged(_ sender: NSSlider) {
            let idx = min(max(Int(sender.doubleValue.rounded()), 0), parent.fibSeconds.count - 1)
            parent.seconds = Double(parent.fibSeconds[idx])
        }
    }
}
