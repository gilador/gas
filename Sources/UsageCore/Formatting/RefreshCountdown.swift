import Foundation

public enum RefreshCountdown {
    /// "in 15 mins", "in 1 min", "in 1 hr 5 mins", "in 2 hrs", "now".
    public static func text(until date: Date, now: Date = Date()) -> String {
        let seconds = date.timeIntervalSince(now)
        guard seconds > 0 else { return "now" }
        let total = Int((seconds / 60).rounded(.up))
        let hours = total / 60
        let minutes = total % 60
        guard hours > 0 else { return "in \(unit(minutes, "min"))" }
        guard minutes > 0 else { return "in \(unit(hours, "hr"))" }
        return "in \(unit(hours, "hr")) \(unit(minutes, "min"))"
    }

    private static func unit(_ value: Int, _ name: String) -> String {
        "\(value) \(name)\(value == 1 ? "" : "s")"
    }
}
