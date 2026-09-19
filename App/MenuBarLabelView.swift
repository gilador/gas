import SwiftUI
import UsageCore

struct MenuBarLabelView: View {
    let board: UsageBoard

    var body: some View {
        Text(UsageFormatter.compactLabel(for: board))
    }
}
