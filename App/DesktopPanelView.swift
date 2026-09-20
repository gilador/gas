import SwiftUI
import UsageCore

struct DesktopPanelView: View {
    @ObservedObject var viewModel: UsageViewModel
    let onSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Tokens").font(.caption.bold())
                Spacer()
                Button(action: onSettings) {
                    Image(systemName: "gearshape")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Settings")
            }
            content
        }
        .padding(14)
        .frame(width: 240, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(red: 0.12, green: 0.22, blue: 0.34))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.white.opacity(0.18), lineWidth: 1)
        )
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.board.isEmpty {
            Text("Loading…").font(.caption).foregroundStyle(.secondary)
        } else {
            ForEach(Array(viewModel.board.snapshots.enumerated()), id: \.element.provider) { index, snapshot in
                if index > 0 { Divider() }
                ProviderSection(snapshot: snapshot)
            }
        }
    }
}
