import XCTest
import Foundation
@testable import UsageCore

final class SecurityCLITokenReaderTests: XCTestCase {
    private final class Recorder: @unchecked Sendable {
        var executable: URL?
        var arguments: [String] = []
    }

    private func reader(status: Int32, output: String = "", recorder: Recorder = Recorder(),
                        throwing: Bool = false) -> SecurityCLITokenReader {
        SecurityCLITokenReader(service: "Claude Code-credentials", account: "user") { executable, arguments in
            recorder.executable = executable
            recorder.arguments = arguments
            if throwing { throw CocoaError(.executableNotLoadable) }
            return (status, Data(output.utf8))
        }
    }

    func testReadsTokenFromSecurityOutput() throws {
        let json = #"{"claudeAiOauth":{"accessToken":"abc123","expiresAt":1750000000000}}"# + "\n"
        let token = try reader(status: 0, output: json).readClaudeToken()
        XCTAssertEqual(token.accessToken, "abc123")
        XCTAssertEqual(token.expiresAt, Date(timeIntervalSince1970: 1_750_000_000))
    }

    func testRunsSecurityWithServiceAndAccount() throws {
        let recorder = Recorder()
        _ = try? reader(status: 0, output: #"{"claudeAiOauth":{"accessToken":"t"}}"#, recorder: recorder).readClaudeToken()
        XCTAssertEqual(recorder.executable?.path, "/usr/bin/security")
        XCTAssertEqual(recorder.arguments, ["find-generic-password", "-s", "Claude Code-credentials", "-a", "user", "-w"])
    }

    func testItemNotFoundExitCodeMapsToNotFound() {
        XCTAssertThrowsError(try reader(status: 44).readClaudeToken()) {
            XCTAssertEqual($0 as? TokenReaderError, .notFound)
        }
    }

    func testOtherExitCodesMapToAccessDenied() {
        for status: Int32 in [1, 36, 51, 128] {
            XCTAssertThrowsError(try reader(status: status).readClaudeToken()) {
                XCTAssertEqual($0 as? TokenReaderError, .accessDenied, "exit \(status)")
            }
        }
    }

    func testLaunchFailureMapsToAccessDenied() {
        XCTAssertThrowsError(try reader(status: 0, throwing: true).readClaudeToken()) {
            XCTAssertEqual($0 as? TokenReaderError, .accessDenied)
        }
    }

    func testBadOutputMapsToMalformed() {
        XCTAssertThrowsError(try reader(status: 0, output: "not json").readClaudeToken()) {
            XCTAssertEqual($0 as? TokenReaderError, .malformed)
        }
    }
}
