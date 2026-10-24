import Foundation

enum RetryAfter {
    static func seconds(from response: HTTPURLResponse, now: Date = Date()) -> TimeInterval {
        guard let raw = response.value(forHTTPHeaderField: "Retry-After")?.trimmingCharacters(in: .whitespaces) else { return 0 }
        if let seconds = wholeSeconds(raw) { return TimeInterval(seconds) }
        guard let date = httpDate(raw) else { return 0 }
        return max(date.timeIntervalSince(now), 0)
    }

    static func logValue(_ raw: String?) -> String {
        guard let raw = raw?.trimmingCharacters(in: .whitespaces) else { return "-" }
        if let seconds = wholeSeconds(raw) { return String(seconds) }
        return httpDate(raw) == nil ? "-" : "date"
    }

    private static func wholeSeconds(_ raw: String) -> Int? {
        guard !raw.isEmpty, raw.count <= 10, raw.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return Int(raw)
    }

    private static func httpDate(_ raw: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        return formatter.date(from: raw)
    }
}
