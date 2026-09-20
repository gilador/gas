import Foundation

enum RetryAfter {
    /// Integer seconds form only; an HTTP-date or a missing header yields 0 (policy decides).
    static func seconds(from response: HTTPURLResponse) -> TimeInterval {
        guard let raw = response.value(forHTTPHeaderField: "Retry-After"),
              let seconds = TimeInterval(raw.trimmingCharacters(in: .whitespaces)), seconds > 0 else { return 0 }
        return seconds
    }
}
