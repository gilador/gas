import SwiftUI
import UsageCore

struct ProviderIcon: View {
    let provider: ProviderID
    var size: CGFloat = 14

    var body: some View {
        if let name = assetName {
            Image(name)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
        } else {
            Text(provider.glyph).font(.system(size: size))
        }
    }

    private var assetName: String? {
        switch provider {
        case .claude: return "ClaudeIcon"
        case .openai: return "OpenAIIcon"
        case .xai: return nil
        }
    }
}
