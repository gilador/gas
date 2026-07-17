import XCTest
@testable import UsageCore

final class CoreInfoTests: XCTestCase {
    func testVersionIsSet() {
        XCTAssertEqual(CoreInfo.version, "0.1.0")
    }
}
