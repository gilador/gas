import XCTest
@testable import UsageCore

final class ClaudeCodeRenewerTests: XCTestCase {
    private final class RunSpy: @unchecked Sendable {
        private let lock = NSLock()
        private var _calls: [(URL, [String])] = []
        let status: Int32?
        init(status: Int32?) { self.status = status }
        var calls: [(URL, [String])] { lock.lock(); defer { lock.unlock() }; return _calls }
        var run: ClaudeCodeRenewer.Runner {
            { [self] executable, arguments in
                lock.lock(); _calls.append((executable, arguments)); lock.unlock()
                return status
            }
        }
    }

    private final class Clock: @unchecked Sendable {
        var now = Date(timeIntervalSince1970: 1_000_000)
    }

    private let claudePath = URL(fileURLWithPath: "/opt/test/claude")

    func testRunsClaudeOnceWithALightHeadlessCall() async {
        let spy = RunSpy(status: 0)
        let renewer = ClaudeCodeRenewer(locate: { [claudePath] in claudePath }, run: spy.run)
        let result = await renewer.renew()
        XCTAssertEqual(result, .renewed)
        XCTAssertEqual(spy.calls.count, 1)
        XCTAssertEqual(spy.calls.first?.0, claudePath)
        let arguments = spy.calls.first?.1 ?? []
        for expected in ["-p", "haiku", "--no-session-persistence", "--strict-mcp-config", "--disable-slash-commands"] {
            XCTAssertTrue(arguments.contains(expected), expected)
        }
        XCTAssertFalse(arguments.contains("--settings"), "the user's hooks must stay on")
        XCTAssertEqual(arguments.firstIndex(of: "--tools").map { arguments[$0 + 1] }, "")
    }

    func testNonZeroExitMeansClaudeCodeIsNotLoggedIn() async {
        let renewer = ClaudeCodeRenewer(locate: { [claudePath] in claudePath }, run: RunSpy(status: 1).run)
        let result = await renewer.renew()
        XCTAssertEqual(result, .failed)
    }

    func testTimeoutIsUnavailable() async {
        let renewer = ClaudeCodeRenewer(locate: { [claudePath] in claudePath }, run: RunSpy(status: nil).run)
        let result = await renewer.renew()
        XCTAssertEqual(result, .unavailable)
    }

    func testMissingClaudeIsUnavailableWithoutRunning() async {
        let spy = RunSpy(status: 0)
        let renewer = ClaudeCodeRenewer(locate: { nil }, run: spy.run)
        let result = await renewer.renew()
        XCTAssertEqual(result, .unavailable)
        XCTAssertTrue(spy.calls.isEmpty)
    }

    func testTriesAtMostOncePerHour() async {
        let spy = RunSpy(status: 0)
        let clock = Clock()
        let renewer = ClaudeCodeRenewer(locate: { [claudePath] in claudePath }, run: spy.run, now: { clock.now })
        _ = await renewer.renew()
        clock.now += 30 * 60
        let tooSoon = await renewer.renew()
        clock.now += 31 * 60
        let later = await renewer.renew()
        XCTAssertEqual(tooSoon, .renewed)
        XCTAssertEqual(later, .renewed)
        XCTAssertEqual(spy.calls.count, 2)
    }

    func testATryWithinTheHourRepeatsTheLastResult() async {
        let spy = RunSpy(status: 1)
        let clock = Clock()
        let renewer = ClaudeCodeRenewer(locate: { [claudePath] in claudePath }, run: spy.run, now: { clock.now })
        _ = await renewer.renew()
        clock.now += 10 * 60
        let repeated = await renewer.renew()
        XCTAssertEqual(repeated, .failed)
        XCTAssertEqual(spy.calls.count, 1)
    }

    func testIsEnabledFollowsTheSetting() {
        XCTAssertFalse(ClaudeCodeRenewer(isEnabled: { false }).isEnabled)
        XCTAssertTrue(ClaudeCodeRenewer(isEnabled: { true }).isEnabled)
    }

    func testRunProcessReportsTheExitStatus() async {
        let success = await ClaudeCodeRenewer.runProcess(URL(fileURLWithPath: "/usr/bin/true"), [])
        let failure = await ClaudeCodeRenewer.runProcess(URL(fileURLWithPath: "/usr/bin/false"), [])
        let missing = await ClaudeCodeRenewer.runProcess(URL(fileURLWithPath: "/nonexistent/claude"), [])
        XCTAssertEqual(success, 0)
        XCTAssertEqual(failure, 1)
        XCTAssertNil(missing)
    }
}
