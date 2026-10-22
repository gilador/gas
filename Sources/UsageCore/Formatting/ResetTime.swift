import Foundation

public enum ResetTime {
    /// "at 4pm", "on Friday at 2am", "on Oct 30 at 2am", or "now".
    public static func text(for reset: Date, now: Date, calendar: Calendar = .current) -> String {
        guard reset > now else { return "now" }
        let rounded = Date(timeIntervalSinceReferenceDate: (reset.timeIntervalSinceReferenceDate / 60).rounded() * 60)
        let time = clock(rounded, calendar: calendar)
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: rounded)).day ?? 0
        switch days {
        case ..<1: return "at \(time)"
        case 1..<7: return "on \(name(rounded, "EEEE", calendar: calendar)) at \(time)"
        default: return "on \(name(rounded, "MMM d", calendar: calendar)) at \(time)"
        }
    }

    /// "6 days, 3 hours and 12 minutes left", or "Resetting now".
    public static func remaining(until reset: Date, now: Date) -> String {
        guard reset > now else { return "Resetting now" }
        let total = Int((reset.timeIntervalSince(now) / 60).rounded(.up))
        let parts = [(total / 1440, "day"), (total % 1440 / 60, "hour"), (total % 60, "minute")]
            .filter { $0.0 > 0 }
            .map { "\($0.0) \($0.1)\($0.0 == 1 ? "" : "s")" }
        let joined = parts.count > 1 ? parts.dropLast().joined(separator: ", ") + " and " + parts[parts.count - 1] : parts[0]
        return joined + " left"
    }

    private static func clock(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let hour = parts.hour ?? 0
        let minute = parts.minute ?? 0
        let twelve = hour % 12 == 0 ? 12 : hour % 12
        let suffix = hour < 12 ? "am" : "pm"
        return minute == 0 ? "\(twelve)\(suffix)" : "\(twelve):" + String(format: "%02d", minute) + suffix
    }

    private static func name(_ date: Date, _ format: String, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
}
