import Foundation

public struct AppVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
    public let parts: [Int]

    public init?(_ text: String) {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.first == "v" || trimmed.first == "V" { trimmed.removeFirst() }
        let pieces = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...4).contains(pieces.count) else { return nil }
        var numbers: [Int] = []
        for piece in pieces {
            guard !piece.isEmpty, piece.allSatisfy({ $0.isASCII && $0.isNumber }), let value = Int(piece) else {
                return nil
            }
            numbers.append(value)
        }
        parts = numbers
    }

    public var description: String { parts.map(String.init).joined(separator: ".") }

    private var normalized: [Int] {
        var trimmed = parts
        while trimmed.count > 1, trimmed.last == 0 { trimmed.removeLast() }
        return trimmed
    }

    public static func == (lhs: AppVersion, rhs: AppVersion) -> Bool { lhs.normalized == rhs.normalized }

    public func hash(into hasher: inout Hasher) { hasher.combine(normalized) }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        for index in 0..<max(lhs.parts.count, rhs.parts.count) {
            let left = index < lhs.parts.count ? lhs.parts[index] : 0
            let right = index < rhs.parts.count ? rhs.parts[index] : 0
            if left != right { return left < right }
        }
        return false
    }
}
