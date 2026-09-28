import XCTest
@testable import UsageCore

final class ProviderIDTests: XCTestCase {
    func testDisplayOrderIsClaudeThenOpenAI() {
        XCTAssertEqual(ProviderID.displayOrder, [.claude, .openai])
    }

    func testDisplayNames() {
        XCTAssertEqual(ProviderID.claude.displayName, "Claude")
        XCTAssertEqual(ProviderID.openai.displayName, "OpenAI")
        XCTAssertEqual(ProviderID.xai.displayName, "xAI")
    }

    func testGlyphs() {
        XCTAssertEqual(ProviderID.claude.glyph, "◐")
        XCTAssertEqual(ProviderID.openai.glyph, "⬡")
    }

    func testSignInHints() {
        XCTAssertEqual(ProviderID.claude.signInHint, "Run /login in Claude Code")
        XCTAssertEqual(ProviderID.openai.signInHint, "Run codex login in Terminal")
    }

    func testClientNames() {
        XCTAssertEqual(ProviderID.claude.clientName, "Claude Code")
        XCTAssertEqual(ProviderID.openai.clientName, "Codex CLI")
    }

    func testEveryCaseHasNonEmptyMetadata() {
        for id in ProviderID.allCases {
            XCTAssertFalse(id.displayName.isEmpty, "\(id)")
            XCTAssertFalse(id.glyph.isEmpty, "\(id)")
            XCTAssertFalse(id.clientName.isEmpty, "\(id)")
        }
    }
}
