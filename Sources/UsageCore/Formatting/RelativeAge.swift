import Foundation

public enum RelativeAge {
    /// "now", "43s ago", "12m ago", "3h ago", "2d ago".
    public static func compact(from date: Date, now: Date = Date()) -> String {
        let seconds = now.timeIntervalSince(date)
        guard seconds >= 1 else { return "now" }
        switch seconds {
        case ..<60: return "\(Int(seconds))s ago"
        case ..<3600: return "\(Int(seconds / 60))m ago"
        case ..<86_400: return "\(Int(seconds / 3600))h ago"
        default: return "\(Int(seconds / 86_400))d ago"
        }
    }
}
