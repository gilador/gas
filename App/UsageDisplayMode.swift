import SwiftUI
import UsageCore

enum UsageDisplayMode: String, CaseIterable {
    case used, remaining

    static let key = "usageDisplay"

    var title: String { self == .used ? "Used" : "Remaining" }

    func percent(for limit: UsageLimit) -> Int {
        self == .used ? limit.displayPercent : max(0, 100 - limit.displayPercent)
    }

    func fraction(for limit: UsageLimit) -> Double {
        let used = min(max(limit.percentUsed, 0), 100) / 100
        return self == .used ? used : 1 - used
    }

    static func current(_ raw: String) -> UsageDisplayMode { UsageDisplayMode(rawValue: raw) ?? .used }
}
