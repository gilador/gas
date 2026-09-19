public enum ProviderID: String, Codable, Sendable, CaseIterable {
    case claude
    case xai
    case openai

    public static let displayOrder: [ProviderID] = [.claude, .openai]

    public var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .openai: return "OpenAI"
        case .xai: return "xAI"
        }
    }

    public var glyph: String {
        switch self {
        case .claude: return "◐"
        case .openai: return "⬡"
        case .xai: return "✕"
        }
    }

    public var clientName: String {
        switch self {
        case .claude: return "Claude Code"
        case .openai: return "Codex CLI"
        case .xai: return "xAI"
        }
    }
}
