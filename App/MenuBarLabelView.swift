import SwiftUI
import UsageCore

struct MenuBarLabelView: View {
    let board: UsageBoard

    var body: some View {
        HStack(spacing: 1) {
            ForEach(Array(ProviderID.displayOrder.enumerated()), id: \.element) { index, provider in
                if index > 0 { Text("|").foregroundStyle(.secondary) }
                ProviderIcon(provider: provider, size: 14)
                Text(percentText(for: provider)).monospacedDigit()
            }
        }
    }

    private func percentText(for provider: ProviderID) -> String {
        board.snapshot(for: provider)?.tightestLimit
            .map { "\(Int($0.percentUsed.rounded()))%" } ?? "—"
    }
}
