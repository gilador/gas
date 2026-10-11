import XCTest
@testable import UsageCore

final class AppVersionTests: XCTestCase {
    func testParsesWithAndWithoutPrefix() {
        XCTAssertEqual(AppVersion("v1.0.24")?.parts, [1, 0, 24])
        XCTAssertEqual(AppVersion("1.0.24")?.parts, [1, 0, 24])
        XCTAssertEqual(AppVersion(" V2.1 \n")?.parts, [2, 1])
    }

    func testComparesNumbersNotText() {
        XCTAssertLessThan(AppVersion("1.0.9")!, AppVersion("1.0.10")!)
        XCTAssertLessThan(AppVersion("1.9.9")!, AppVersion("2.0")!)
        XCTAssertFalse(AppVersion("1.0.24")! < AppVersion("1.0.24")!)
    }

    func testMissingPartsCountAsZero() {
        XCTAssertEqual(AppVersion("1.0")!, AppVersion("1.0.0")!)
        XCTAssertEqual(Set([AppVersion("1.0")!, AppVersion("1.0.0")!]).count, 1)
        XCTAssertFalse(AppVersion("1.0")! < AppVersion("1.0.0")!)
    }

    func testRejectsBadInput() {
        for text in ["", "v", "1..2", "1.0.24-beta", "nightly", "1.0.0.0.1", "1.-2", "1.0.٣"] {
            XCTAssertNil(AppVersion(text), text)
        }
    }

    func testDescriptionDropsThePrefix() {
        XCTAssertEqual(AppVersion("v1.0.24")?.description, "1.0.24")
    }
}
