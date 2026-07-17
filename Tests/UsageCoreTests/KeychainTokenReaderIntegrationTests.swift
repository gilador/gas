import Foundation
import XCTest
@testable import UsageCore

final class KeychainTokenReaderIntegrationTests: XCTestCase {
    func testReadsRealTokenIfPresent() throws {
        guard ProcessInfo.processInfo.environment["RUN_KEYCHAIN_INTEGRATION_TESTS"] != nil else {
            throw XCTSkip("Set RUN_KEYCHAIN_INTEGRATION_TESTS=1 to exercise the real keychain")
        }
        let reader = KeychainTokenReader()
        do {
            let token = try reader.readClaudeToken()
            XCTAssertFalse(token.accessToken.isEmpty)
        } catch TokenReaderError.notFound {
            throw XCTSkip("Claude Code-credentials item not present")
        } catch TokenReaderError.accessDenied {
            throw XCTSkip("Keychain access not granted to the test runner")
        }
    }
}
