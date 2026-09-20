import SwiftUI
import UsageCore

enum LimitPalette {
    static func color(for limit: UsageLimit) -> Color {
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
        default: return Color(red: 0.55, green: 0.75, blue: 1.0)
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
