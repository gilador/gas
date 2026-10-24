import Foundation

public enum GrokHTTPClientError: Error, Equatable {
    case disallowedURL
    case responseTooLarge
}

public final class GrokHTTPClient: UsageHTTPClient {
    public static let billingURL = URL(string: "https://cli-chat-proxy.grok.com/v1/billing?format=credits")!
    static let maximumBodySize = 256 * 1024

    private let session: URLSession

    public convenience init() {
        self.init(protocolClasses: nil)
    }

    init(protocolClasses: [AnyClass]?) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        if let protocolClasses { configuration.protocolClasses = protocolClasses }
        session = URLSession(configuration: configuration, delegate: RedirectRefusal(), delegateQueue: nil)
    }

    deinit { session.finishTasksAndInvalidate() }

    var configuration: URLSessionConfiguration { session.configuration }

    public func get(_ url: URL, headers: [String: String]) async throws -> (Data, HTTPURLResponse) {
        guard url.absoluteString == Self.billingURL.absoluteString else { throw GrokHTTPClientError.disallowedURL }
        var request = URLRequest(url: Self.billingURL)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            bytes.task.cancel()
            throw URLError(.badServerResponse)
        }
        guard http.expectedContentLength <= Self.maximumBodySize else {
            bytes.task.cancel()
            throw GrokHTTPClientError.responseTooLarge
        }
        var data = Data()
        for try await byte in bytes {
            guard data.count < Self.maximumBodySize else {
                bytes.task.cancel()
                throw GrokHTTPClientError.responseTooLarge
            }
            data.append(byte)
        }
        return (data, http)
    }
}

private final class RedirectRefusal: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        nil
    }
}
