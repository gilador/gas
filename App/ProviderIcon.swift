import SwiftUI
import UsageCore

struct ProviderIcon: View {
    let provider: ProviderID
    var size: CGFloat = 14

    var body: some View {
        if let name = assetName {
            Image(name)
                .renderingMode(.template)
                .resizable()
                .interpolation(.high)
                .frame(width: size * glyphScale, height: size * glyphScale)
                .frame(width: size, height: size)
                .foregroundStyle(tint)
        } else {
            Text(provider.glyph)
                .font(.system(size: size * 0.85, weight: .semibold))
                .frame(width: size, height: size)
                .foregroundStyle(tint)
        }
    }

    /// The Claude template glyph carries more padding than the OpenAI one; scale it to match optically.
    private var glyphScale: CGFloat { provider == .claude ? 1.3 : 1.0 }

    private var tint: Color {
        provider == .claude ? Color(red: 0.85, green: 0.47, blue: 0.34) : .primary
    }

    private var assetName: String? {
        switch provider {
        case .claude: return "ClaudeIcon"
        case .openai: return "OpenAIIcon"
        case .xai: return nil
        }
    }
}
