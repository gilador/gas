import XCTest
@testable import UsageCore

@MainActor
final class SetupFlowTests: XCTestCase {
    private final class Login: SetupRunningLogin {
        var terminated = false
        func terminate() { terminated = true }
    }

    private final class FakeRunner: SetupRunner {
        var path: URL? = URL(fileURLWithPath: "/opt/test/claude")
        var installResult = ProcessOutput(exitCode: 0, output: "")
        var checks: [LoginStatus] = [.loggedIn]
        var refreshed: FetchStatus? = .ok
        var installCalls = 0
        var loginCalls = 0
        var refreshCalls = 0
        var sleepCalls = 0
        var onSleep: (() -> Void)?
        let login = Login()

        func locate(_ tool: CLITool) async -> URL? { path }
        func install(_ tool: CLITool) async -> ProcessOutput {
            installCalls += 1
            if installResult.exitCode == 0 { path = URL(fileURLWithPath: "/opt/test/claude") }
            return installResult
        }
        func startLogin(_ tool: CLITool, executable: URL) async -> (any SetupRunningLogin)? {
            loginCalls += 1
            return login
        }
        func checkLogin(_ tool: CLITool, executable: URL) async -> LoginStatus {
            checks.isEmpty ? .loggedOut : checks.removeFirst()
        }
        func sleepForStatusCheck() async {
            sleepCalls += 1
            onSleep?()
        }
        func refresh(_ provider: ProviderID) async -> FetchStatus? {
            refreshCalls += 1
            return refreshed
        }
    }

    func testFullInstallLoginAndRefreshSuccess() async {
        let runner = FakeRunner()
        runner.path = nil
        runner.checks = [.loggedOut, .loggedOut, .loggedIn]
        let flow = SetupFlow(tool: .claude, runner: runner, pollLimit: 3)
        await flow.setUp()
        XCTAssertEqual(flow.state, .ready)
        XCTAssertEqual(runner.installCalls, 1)
        XCTAssertEqual(runner.loginCalls, 1)
        XCTAssertEqual(runner.sleepCalls, 2)
        XCTAssertEqual(runner.refreshCalls, 1)
        XCTAssertTrue(runner.login.terminated)
    }

    func testInstallFailureShowsLastOutputLineAndDoesNotSignIn() async {
        let runner = FakeRunner()
        runner.path = nil
        runner.installResult = ProcessOutput(exitCode: 1, output: "downloading\nnetwork failed\n")
        let flow = SetupFlow(tool: .claude, runner: runner)
        await flow.setUp()
        XCTAssertEqual(flow.state, .installFailed("network failed"))
        XCTAssertEqual(runner.loginCalls, 0)
        XCTAssertEqual(runner.refreshCalls, 0)
    }

    func testSignInTimeoutStopsProcess() async {
        let runner = FakeRunner()
        runner.checks = [.loggedOut, .loggedOut, .loggedOut]
        let flow = SetupFlow(tool: .claude, runner: runner, pollLimit: 2)
        await flow.setUp()
        XCTAssertEqual(flow.state, .loginTimedOut)
        XCTAssertTrue(runner.login.terminated)
        XCTAssertEqual(runner.refreshCalls, 0)
    }

    func testCancelStopsChecksAndSignInProcess() async {
        let runner = FakeRunner()
        runner.checks = [.loggedOut, .loggedOut]
        let flow = SetupFlow(tool: .claude, runner: runner, pollLimit: 150)
        runner.onSleep = { flow.cancel() }
        await flow.setUp()
        XCTAssertEqual(flow.state, .cancelled)
        XCTAssertTrue(runner.login.terminated)
        XCTAssertEqual(runner.sleepCalls, 1)
        XCTAssertEqual(runner.refreshCalls, 0)
    }

    func testTryAgainChecksLoginThenRefreshesOnce() async {
        let runner = FakeRunner()
        let flow = SetupFlow(tool: .claude, runner: runner)
        await flow.tryAgain()
        XCTAssertEqual(flow.state, .ready)
        XCTAssertEqual(runner.installCalls, 0)
        XCTAssertEqual(runner.loginCalls, 0)
        XCTAssertEqual(runner.refreshCalls, 1)
    }

    func testCachedGoodUsageDoesNotHideMissingCLI() async {
        let runner = FakeRunner()
        runner.path = nil
        let flow = SetupFlow(tool: .claude, runner: runner)
        await flow.inspect(enabled: true, fetchStatus: .ok)
        XCTAssertEqual(flow.state, .cliMissing)
    }

    func testCachedGoodUsageDoesNotHideLoggedOutCLIButToleratesUnknownStatus() async {
        let runner = FakeRunner()
        runner.checks = [.loggedOut, .unknown]
        let flow = SetupFlow(tool: .claude, runner: runner)
        await flow.inspect(enabled: true, fetchStatus: .ok)
        XCTAssertEqual(flow.state, .notLoggedIn)
        await flow.inspect(enabled: true, fetchStatus: .ok)
        XCTAssertEqual(flow.state, .ready)
    }
}
