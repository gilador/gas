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
