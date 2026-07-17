import XCTest
@testable import UsageCore

final class KeychainTokenReaderIntegrationTests: XCTestCase {
    func testReadsRealTokenIfPresent() throws {
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
