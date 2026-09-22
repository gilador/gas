import Foundation

public enum AlertBlink {
    public static let blinks = 10
    public static let period: TimeInterval = 0.5
    /// Total time from the first "on" to the last "off".
    public static var duration: TimeInterval { Double(blinks) * period * 2 }

    public static func isOn(elapsed: TimeInterval) -> Bool {
        guard elapsed >= 0, elapsed < duration else { return false }
        return Int(elapsed / period) % 2 == 0
    }
}
