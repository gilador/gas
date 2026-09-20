import SwiftUI
import UsageCore

struct DesktopPanelView: View {
    @ObservedObject var viewModel: UsageViewModel
    let onSettings: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Spacer()
                Button(action: onSettings) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Settings")
            }
            content
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .frame(width: 72, alignment: .top)
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
            Text("…").font(.caption).foregroundStyle(.secondary)
        } else {
            ForEach(Array(viewModel.board.snapshots.enumerated()), id: \.element.provider) { index, snapshot in
                if index > 0 {
                    Rectangle().fill(.white.opacity(0.15)).frame(width: 40, height: 1)
                }
                ProviderStripItem(snapshot: snapshot)
            }
        }
    }
}
