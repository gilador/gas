import Foundation

enum MenuBarSize {
    static let key = "menuBarFontSize"
    static let defaultFontSize = 12.0
    static let range: ClosedRange<Double> = 12...18
    static let recommendedMax = 16.0

    static func fontSize(_ raw: Double) -> Double { min(max(raw, range.lowerBound), range.upperBound) }
    static func iconSize(for font: Double) -> Double { font + 2 }
}
