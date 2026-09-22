import SwiftUI
import UsageCore

struct MenuBarLabelView: View {
    @ObservedObject var viewModel: UsageViewModel
    @AppStorage(UsageDisplayMode.key) private var usageDisplayRaw = UsageDisplayMode.used.rawValue
    @AppStorage(ProviderSettings.key(.claude)) private var claudeEnabled = true
    @AppStorage(ProviderSettings.key(.openai)) private var openaiEnabled = true
    private var mode: UsageDisplayMode { .current(usageDisplayRaw) }

    var body: some View {
        let _ = (claudeEnabled, openaiEnabled)
        HStack(spacing: 2) {
            ForEach(Array(ProviderSettings.enabled().enumerated()), id: \.element) { index, provider in
                if index > 0 {
                    Text("|").padding(.horizontal, 1)
                }
                ProviderIcon(provider: provider, size: 14)
                Text(percentText(for: provider))
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
            }
        }
        .padding(.horizontal, 4)
        .fixedSize()
    }

    private func percentText(for provider: ProviderID) -> String {
        viewModel.board.snapshot(for: provider)?.tightestLimit
            .map { "\(mode.percent(for: $0))%" } ?? "—"
    }
}
