import Foundation

public struct ProviderRegistry {
    public let providers: [any UsageProvider]

    public init(providers: [any UsageProvider]) {
        self.providers = providers
    }

    public static func makeDefault(tokenReader: TokenReader,
                                   codexAuthReader: CodexAuthReader,
                                   grokAuthReader: GrokAuthReader,
                                   httpClient: UsageHTTPClient,
                                   claudeBaseURL: URL,
                                   openAIBaseURL: URL,
                                   claudeRenewer: TokenRenewer? = nil) -> ProviderRegistry {
        ProviderRegistry(providers: [
            ClaudeUsageProvider(tokenReader: tokenReader,
                                httpClient: httpClient,
                                baseURL: claudeBaseURL,
                                renewer: claudeRenewer),
            OpenAIUsageProvider(authReader: codexAuthReader,
                                httpClient: httpClient,
                                baseURL: openAIBaseURL),
            XAIUsageProvider(authReader: grokAuthReader, httpClient: GrokHTTPClient())
        ])
    }
}
