public enum UsageFormatter {
    public static func compactLabel(for board: UsageBoard) -> String {
        let parts = board.tightestLimits.map {
            "\($0.provider.glyph)\(Int($0.limit.percentUsed.rounded()))%"
        }
        return parts.isEmpty ? "◐—" : parts.joined(separator: "·")
    }
}
