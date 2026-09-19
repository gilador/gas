import Foundation
@testable import UsageCore

struct StubTokenReader: TokenReader, @unchecked Sendable {
    let result: Result<ClaudeToken, Error>
    func readClaudeToken() throws -> ClaudeToken { try result.get() }
}

final class StubHTTPClient: UsageHTTPClient, @unchecked Sendable {
    let data: Data
    let statusCode: Int
    init(data: Data, statusCode: Int) {
        self.data = data
        self.statusCode = statusCode
    }
    func get(_ url: URL, headers: [String: String]) async throws -> (Data, HTTPURLResponse) {
        let resp = HTTPURLResponse(url: url, statusCode: statusCode,
                                   httpVersion: nil, headerFields: nil)!
        return (data, resp)
    }
}

/// An HTTP client that always throws the given error (e.g. a URLError for offline).
struct ThrowingHTTPClient: UsageHTTPClient, @unchecked Sendable {
    let error: Error
    func get(_ url: URL, headers: [String: String]) async throws -> (Data, HTTPURLResponse) {
        throw error
    }
}

struct StubError: Error {}

/// Records every request; returns the configured body and status.
final class SpyHTTPClient: UsageHTTPClient, @unchecked Sendable {
    struct Call { let url: URL; let headers: [String: String] }
    private let lock = NSLock()
    private var _calls: [Call] = []
    var calls: [Call] { lock.lock(); defer { lock.unlock() }; return _calls }
    let data: Data
    let statusCode: Int
    init(data: Data = Data(), statusCode: Int = 200) {
        self.data = data
        self.statusCode = statusCode
    }
    func get(_ url: URL, headers: [String: String]) async throws -> (Data, HTTPURLResponse) {
        lock.lock(); _calls.append(Call(url: url, headers: headers)); lock.unlock()
        let resp = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
        return (data, resp)
    }
}

struct StubUsageProvider: UsageProvider, @unchecked Sendable {
    let id: ProviderID
    let result: Result<UsageSnapshot, Error>
    var delay: TimeInterval = 0
    func fetch() async throws -> UsageSnapshot {
        if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
        return try result.get()
    }
}

struct StubCodexAuthReader: CodexAuthReader, @unchecked Sendable {
    let result: Result<CodexAuth, Error>
    func readCodexAuth() throws -> CodexAuth { try result.get() }
}
