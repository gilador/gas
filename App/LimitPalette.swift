import SwiftUI
import UsageCore

enum LimitPalette {
    static func color(for limit: UsageLimit) -> Color {
        if limit.id.hasPrefix("weekly_scoped") { return .gray }
        switch limit.severity {
        case .critical: return .red
        case .warning: return .orange
        case .normal: return windowColor(for: limit)
        }
    }

    static func windowColor(for limit: UsageLimit) -> Color {
        switch limit.id {
        case "session": return .green
        case "weekly_all": return .white
        default: return .gray
        }
    }
}

struct LimitBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.15))
                Capsule().fill(color).frame(width: proxy.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 6)
    }
}
