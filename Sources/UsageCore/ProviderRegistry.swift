import Foundation

public struct ProviderRegistry {
    public let providers: [any UsageProvider]

    public init(providers: [any UsageProvider]) {
        self.providers = providers
    }

    public static func makeDefault(tokenReader: TokenReader,
                                   codexAuthReader: CodexAuthReader,
                                   httpClient: UsageHTTPClient,
                                   claudeBaseURL: URL,
                                   openAIBaseURL: URL) -> ProviderRegistry {
        ProviderRegistry(providers: [
            ClaudeUsageProvider(tokenReader: tokenReader,
                                httpClient: httpClient,
                                baseURL: claudeBaseURL),
            OpenAIUsageProvider(authReader: codexAuthReader,
                                httpClient: httpClient,
                                baseURL: openAIBaseURL)
        ])
    }
}
