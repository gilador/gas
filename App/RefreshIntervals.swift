import Foundation

enum RefreshIntervals {
    static let stopsSeconds: [Double] = [15, 20, 30, 45, 60].map { $0 * 60 }
    static let defaultSeconds: Double = 15 * 60

    static func snapped(_ seconds: Double) -> Double {
        stopsSeconds.min(by: { abs($0 - seconds) < abs($1 - seconds) }) ?? defaultSeconds
    }
}
