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
                                   openAIBaseURL: URL,
                                   claudeLocalReader: ClaudeLocalUsageReader? = nil) -> ProviderRegistry {
        ProviderRegistry(providers: [
            ClaudeUsageProvider(tokenReader: tokenReader,
                                httpClient: httpClient,
                                baseURL: claudeBaseURL,
                                localReader: claudeLocalReader),
            OpenAIUsageProvider(authReader: codexAuthReader,
                                httpClient: httpClient,
                                baseURL: openAIBaseURL)
        ])
    }
}
