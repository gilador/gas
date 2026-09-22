public enum UsageFormatter {
    public static func compactLabel(for board: UsageBoard) -> String {
        ProviderID.displayOrder.map { provider in
            let percent = board.snapshot(for: provider)?.tightestLimit
                .map { "\($0.displayPercent)%" } ?? "—"
            return "\(provider.glyph)\(percent)"
        }.joined(separator: "|")
    }
}
