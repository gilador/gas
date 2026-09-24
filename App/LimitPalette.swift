import SwiftUI
import UsageCore

enum LimitPalette {
    static func color(for limit: UsageLimit) -> Color {
        if limit.id.hasPrefix("weekly_scoped") { return perModel(limit.percentUsed) }
        switch limit.severity {
        case .critical: return .red
        case .warning: return .orange
        case .normal: return windowColor(for: limit)
        }
    }

    /// Purple for per-model limits, deepening from light lavender at 0% to dark purple at 100%.
    static func perModel(_ percent: Double) -> Color {
        let t = min(max(percent, 0), 100) / 100
        return Color(hue: 0.77, saturation: 0.3 + 0.6 * t, brightness: 0.95 - 0.4 * t)
    }

    /// The weekly layer drawn behind the session in the strip: a darker shade of the same scale.
    static func backLayerColor(for limit: UsageLimit) -> Color {
        switch limit.severity {
        case .critical: return Color(red: 0.55, green: 0.13, blue: 0.13)
        case .warning: return Color(red: 0.62, green: 0.36, blue: 0.06)
        case .normal: return Color(red: 0.13, green: 0.45, blue: 0.24)
        }
    }

    static func windowColor(for limit: UsageLimit) -> Color {
        switch limit.id {
        case "session": return .green
        case "weekly_all": return .white
        default: return perModel(limit.percentUsed)
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
