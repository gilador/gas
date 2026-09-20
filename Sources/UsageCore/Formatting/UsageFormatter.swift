public enum UsageFormatter {
    public static func compactLabel(for board: UsageBoard) -> String {
        ProviderID.displayOrder.map { provider in
            let percent = board.snapshot(for: provider)?.tightestLimit
                .map { "\(Int($0.percentUsed.rounded()))%" } ?? "—"
            return "\(provider.glyph)\(percent)"
        }.joined(separator: "|")
    }
}
