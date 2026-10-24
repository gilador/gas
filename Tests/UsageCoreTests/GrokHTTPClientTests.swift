import XCTest
import Foundation
@testable import UsageCore

final class GrokStubProtocol: URLProtocol {
    struct Reply {
        var status = 200
        var headers: [String: String] = [:]
        var body = Data()
        var redirectTo: URL?
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var _reply = Reply()
    nonisolated(unsafe) private static var _requests: [URLRequest] = []

    static var reply: Reply {
        get { lock.lock(); defer { lock.unlock() }; return _reply }
        set { lock.lock(); _reply = newValue; lock.unlock() }
    }
    static var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return _requests }
    static func reset() { lock.lock(); _reply = Reply(); _requests = []; lock.unlock() }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock(); Self._requests.append(request); let reply = Self._reply; Self.lock.unlock()
        let url = request.url!
        var headers = reply.headers
        if let target = reply.redirectTo {
            headers["Location"] = target.absoluteString
            let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: headers)!
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: target), redirectResponse: response)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: reply.body)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class GrokHTTPClientTests: XCTestCase {
    private let billing = URL(string: "https://cli-chat-proxy.grok.com/v1/billing?format=credits")!
    private var client: GrokHTTPClient!

    override func setUp() {
        GrokStubProtocol.reset()
        client = GrokHTTPClient(protocolClasses: [GrokStubProtocol.self])
    }

    func testBillingURLIsTheFixedEndpoint() {
        XCTAssertEqual(GrokHTTPClient.billingURL, billing)
    }

    func testReturnsBodyAndStatus() async throws {
        GrokStubProtocol.reply = .init(status: 200, body: Data(#"{"config":{}}"#.utf8))
        let (data, response) = try await client.get(billing, headers: ["Authorization": "Bearer SECRET-MARKER-1"])
        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(data, Data(#"{"config":{}}"#.utf8))
        XCTAssertEqual(GrokStubProtocol.requests.count, 1)
        XCTAssertEqual(GrokStubProtocol.requests.first?.httpMethod, "GET")
        XCTAssertEqual(GrokStubProtocol.requests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer SECRET-MARKER-1")
    }

    func testRedirectIsNotFollowed() async throws {
        GrokStubProtocol.reply = .init(status: 302, redirectTo: URL(string: "https://attacker.example.com/collect")!)
        let (_, response) = try await client.get(billing, headers: ["Authorization": "Bearer SECRET-MARKER-1"])
        XCTAssertEqual(response.statusCode, 302)
        XCTAssertEqual(GrokStubProtocol.requests.map(\.url), [billing])
    }

    func testOversizedBodyThrows() async {
        GrokStubProtocol.reply = .init(status: 200, body: Data(count: 256 * 1024 + 1))
        do {
            _ = try await client.get(billing, headers: [:])
            XCTFail("expected a throw")
        } catch {
            XCTAssertEqual(error as? GrokHTTPClientError, .responseTooLarge)
        }
    }

    func testOversizedDeclaredLengthThrows() async {
        GrokStubProtocol.reply = .init(status: 200, headers: ["Content-Length": "\(10 * 1024 * 1024)"], body: Data(count: 16))
        do {
            _ = try await client.get(billing, headers: [:])
            XCTFail("expected a throw")
        } catch {
            XCTAssertEqual(error as? GrokHTTPClientError, .responseTooLarge)
        }
    }

    func testBodyAtTheCapIsAccepted() async throws {
        GrokStubProtocol.reply = .init(status: 200, body: Data(count: 256 * 1024))
        let (data, _) = try await client.get(billing, headers: [:])
        XCTAssertEqual(data.count, 256 * 1024)
    }

    func testOtherURLsAreRejectedBeforeTheNetwork() async {
        let others = [
            "http://cli-chat-proxy.grok.com/v1/billing?format=credits",
            "https://cli-chat-proxy.grok.com:8443/v1/billing?format=credits",
            "https://evil.example.com/v1/billing?format=credits",
            "https://cli-chat-proxy.grok.com.evil.example.com/v1/billing?format=credits",
            "https://user@cli-chat-proxy.grok.com/v1/billing?format=credits",
            "https://cli-chat-proxy.grok.com/v1/billing",
            "https://cli-chat-proxy.grok.com/v1/billing?format=credits&x=1",
            "https://cli-chat-proxy.grok.com/v1/other?format=credits"
        ]
        for other in others {
            do {
                _ = try await client.get(URL(string: other)!, headers: [:])
                XCTFail("accepted \(other)")
            } catch {
                XCTAssertEqual(error as? GrokHTTPClientError, .disallowedURL, other)
            }
        }
        XCTAssertTrue(GrokStubProtocol.requests.isEmpty)
    }

    func testSessionKeepsNothing() {
        let configuration = GrokHTTPClient().configuration
        XCTAssertNil(configuration.urlCache)
        XCTAssertNil(configuration.httpCookieStorage)
        XCTAssertNil(configuration.urlCredentialStorage)
        XCTAssertFalse(configuration.httpShouldSetCookies)
        XCTAssertEqual(configuration.timeoutIntervalForRequest, 15)
        XCTAssertEqual(configuration.timeoutIntervalForResource, 30)
    }
}
