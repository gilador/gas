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
    let responseHeaders: [String: String]
    init(data: Data = Data(), statusCode: Int = 200, responseHeaders: [String: String] = [:]) {
        self.data = data
        self.statusCode = statusCode
        self.responseHeaders = responseHeaders
    }
    private func record(_ call: Call) {
        lock.lock(); defer { lock.unlock() }
        _calls.append(call)
    }
    func get(_ url: URL, headers: [String: String]) async throws -> (Data, HTTPURLResponse) {
        record(Call(url: url, headers: headers))
        let resp = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: responseHeaders)!
        return (data, resp)
    }
}

struct StubUsageProvider: UsageProvider, @unchecked Sendable {
    let id: ProviderID
    let result: Result<UsageSnapshot, Error>
    var delay: TimeInterval = 0
    var minimumInterval: TimeInterval = 0
    var manualMinimumInterval: TimeInterval = 60
    func fetch() async throws -> UsageSnapshot {
        if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
        return try result.get()
    }
}

struct StubCodexAuthReader: CodexAuthReader, @unchecked Sendable {
    let result: Result<CodexAuth, Error>
    func readCodexAuth() throws -> CodexAuth { try result.get() }
}

final class CountingUsageProvider: UsageProvider, @unchecked Sendable {
    let id: ProviderID
    let result: Result<UsageSnapshot, Error>
    let minimumInterval: TimeInterval
    let manualMinimumInterval: TimeInterval
    var fingerprint: String?
    private let lock = NSLock()
    private var _calls = 0
    var calls: Int { lock.lock(); defer { lock.unlock() }; return _calls }
    init(id: ProviderID, result: Result<UsageSnapshot, Error>, minimumInterval: TimeInterval = 0,
         manualMinimumInterval: TimeInterval = 60) {
        self.id = id
        self.result = result
        self.minimumInterval = minimumInterval
        self.manualMinimumInterval = manualMinimumInterval
    }
    private func recordCall() {
        lock.lock(); defer { lock.unlock() }
        _calls += 1
    }
    func fetch() async throws -> UsageSnapshot { recordCall(); return try result.get() }
    func credentialFingerprint() -> String? { fingerprint }
}

/// Returns the results in order, then repeats the last one.
final class SequenceTokenReader: TokenReader, @unchecked Sendable {
    private let lock = NSLock()
    private var results: [Result<ClaudeToken, Error>]
    init(_ results: [Result<ClaudeToken, Error>]) { self.results = results }
    func readClaudeToken() throws -> ClaudeToken {
        lock.lock()
        let result = results.count > 1 ? results.removeFirst() : results[0]
        lock.unlock()
        return try result.get()
    }
}

final class StubRenewer: TokenRenewer, @unchecked Sendable {
    let isEnabled: Bool
    private let succeeds: Bool
    private let lock = NSLock()
    private var _calls = 0
    var calls: Int { lock.lock(); defer { lock.unlock() }; return _calls }
    init(isEnabled: Bool = true, succeeds: Bool) {
        self.isEnabled = isEnabled
        self.succeeds = succeeds
    }
    func renew() async -> Bool {
        lock.lock(); _calls += 1; lock.unlock()
        return succeeds
    }
}
