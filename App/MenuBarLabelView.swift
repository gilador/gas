import SwiftUI
import UsageCore

struct MenuBarLabelView: View {
    @ObservedObject var viewModel: UsageViewModel
    @ObservedObject private var updates = UpdateModel.shared
    @AppStorage(UsageDisplayMode.key) private var usageDisplayRaw = UsageDisplayMode.remaining.rawValue
    @AppStorage(MenuBarSize.key) private var menuBarFontSize = MenuBarSize.defaultFontSize
    @AppStorage(ProviderSettings.key(.claude)) private var claudeEnabled = true
    @AppStorage(ProviderSettings.key(.openai)) private var openaiEnabled = true
    @AppStorage(ProviderSettings.key(.xai)) private var xaiEnabled = ProviderID.xai.isEnabledByDefault
    private var mode: UsageDisplayMode { .current(usageDisplayRaw) }
    private var fontSize: Double { MenuBarSize.fontSize(menuBarFontSize) }

    var body: some View {
        let _ = (claudeEnabled, openaiEnabled, xaiEnabled)
        HStack(spacing: 2) {
            ForEach(Array(ProviderSettings.enabled().enumerated()), id: \.element) { index, provider in
                if index > 0 {
                    Text("|").padding(.horizontal, 1)
                }
                ProviderIcon(provider: provider, size: MenuBarSize.iconSize(for: fontSize))
                Text(percentText(for: provider))
                    .font(.system(size: fontSize, weight: .medium).monospacedDigit())
            }
        }
        .padding(.horizontal, 4)
        .overlay(alignment: .topTrailing) {
            if updates.showsDot {
                Circle().fill(Color.accentColor).frame(width: 5, height: 5)
            }
        }
        .fixedSize()
    }

    private func percentText(for provider: ProviderID) -> String {
        viewModel.board.snapshot(for: provider)?.headlineLimit
            .map { "\(mode.percent(for: $0))%" } ?? "—"
    }
}
