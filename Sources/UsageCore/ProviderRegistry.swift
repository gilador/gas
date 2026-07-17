import Foundation

public struct ProviderRegistry {
    public let providers: [any UsageProvider]

    public init(providers: [any UsageProvider]) {
        self.providers = providers
    }

    public static func makeDefault(tokenReader: TokenReader,
                                   httpClient: UsageHTTPClient,
                                   baseURL: URL) -> ProviderRegistry {
        ProviderRegistry(providers: [
            ClaudeUsageProvider(tokenReader: tokenReader,
                                httpClient: httpClient,
                                baseURL: baseURL)
        ])
    }
}
