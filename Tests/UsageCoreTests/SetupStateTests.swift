import XCTest
@testable import UsageCore

final class SetupStateTests: XCTestCase {
    private let deadline = Date(timeIntervalSince1970: 1_000)

    func testEveryProviderRowState() {
        XCTAssertEqual(SetupState.resolve(installed: true, loggedIn: true, enabled: true, fetchStatus: .ok), .ready)
        XCTAssertEqual(SetupState.resolve(installed: false, loggedIn: nil, enabled: true, fetchStatus: nil), .cliMissing)
        XCTAssertEqual(SetupState.resolve(installed: true, loggedIn: false, enabled: true, fetchStatus: .needsSignIn), .notLoggedIn)
        XCTAssertEqual(SetupState.resolve(installed: true, loggedIn: true, enabled: true,
                                          fetchStatus: .rateLimited(until: deadline, wait: 60)), .rateLimited(deadline))
        XCTAssertEqual(SetupState.resolve(installed: true, loggedIn: true, enabled: true,
                                          fetchStatus: .error(message: "offline")), .readError("offline"))
        XCTAssertEqual(SetupState.resolve(installed: false, loggedIn: false, enabled: false, fetchStatus: nil), .turnedOff)
        XCTAssertEqual(SetupState.resolve(installed: true, loggedIn: true, enabled: true,
                                          fetchStatus: .ok, step: .installing), .installing)
        XCTAssertEqual(SetupState.resolve(installed: true, loggedIn: true, enabled: true,
                                          fetchStatus: .ok, step: .waitingForSignIn), .waitingForSignIn)
        XCTAssertEqual(SetupState.resolve(installed: true, loggedIn: true, enabled: true,
                                          fetchStatus: .ok, step: .readingUsage), .readingUsage)
        XCTAssertEqual(SetupState.resolve(installed: true, loggedIn: true, enabled: true,
                                          fetchStatus: .ok, failure: .installFailed("network")), .installFailed("network"))
        XCTAssertEqual(SetupState.resolve(installed: true, loggedIn: true, enabled: true,
                                          fetchStatus: .ok, failure: .binaryNotFound), .binaryNotFound)
        XCTAssertEqual(SetupState.resolve(installed: true, loggedIn: true, enabled: true,
                                          fetchStatus: .ok, failure: .loginTimedOut), .loginTimedOut)
        XCTAssertEqual(SetupState.resolve(installed: true, loggedIn: true, enabled: true,
                                          fetchStatus: .ok, failure: .loginCheckFailed), .loginCheckFailed)
    }

    func testClaudeLoginJSONParser() {
        XCTAssertEqual(CLITool.claude.parseLoginStatus(output: #"{"loggedIn":true,"authMethod":"claudeai"}"#, exitCode: 0), .loggedIn)
        XCTAssertEqual(CLITool.claude.parseLoginStatus(output: #"{"loggedIn":false}"#, exitCode: 0), .loggedOut)
        XCTAssertEqual(CLITool.claude.parseLoginStatus(output: "bad", exitCode: 0), .unknown)
        XCTAssertEqual(CLITool.claude.parseLoginStatus(output: #"{"loggedIn":true}"#, exitCode: 1), .unknown)
    }

    func testCodexExitCodeParser() {
        XCTAssertEqual(CLITool.codex.parseLoginStatus(output: "anything", exitCode: 0), .loggedIn)
        XCTAssertEqual(CLITool.codex.parseLoginStatus(output: "", exitCode: 1), .loggedOut)
        XCTAssertEqual(CLITool.codex.parseLoginStatus(output: "", exitCode: nil), .unknown)
    }

    func testGrokToolIsTheGrokCLIForXAI() {
        XCTAssertEqual(CLITool.grok.provider, .xai)
        XCTAssertEqual(CLITool.grok.displayName, "Grok CLI")
        XCTAssertEqual(CLITool.grok.installerURL.absoluteString, "https://x.ai/cli/install.sh")
        XCTAssertEqual(CLITool.grok.installerShell, "/bin/bash")
        XCTAssertEqual(CLITool.grok.loginArguments, ["login"])
    }

    func testOnlyGrokChecksItsLoginWithoutRunningTheCLI() {
        XCTAssertEqual(CLITool.claude.loginCheck, .command(["auth", "status"]))
        XCTAssertEqual(CLITool.codex.loginCheck, .command(["login", "status"]))
        XCTAssertEqual(CLITool.grok.loginCheck, .grokSignIn)
    }

    func testGrokLocatesItsOwnBinary() async {
        let expected = "/tmp/home/.grok/bin/grok"
        let found = await CLITool.grok.locate(home: "/tmp/home", isExecutable: { $0 == expected }, shellLookup: { _ in
            XCTFail("Known path should avoid shell lookup")
            return nil
        })
        XCTAssertEqual(found?.path, expected)
    }

    func testGrokLoginStatusComesFromTheSignInEntryAndItsExpiry() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        func status(_ result: Result<GrokAuth, Error>) -> LoginStatus {
            CLITool.grokLoginStatus(reader: StubGrokAuthReader(result: result), now: now)
        }
        func auth(expiresIn seconds: TimeInterval) -> GrokAuth {
            GrokAuth(accessToken: "fake-token", expiresAt: now.addingTimeInterval(seconds), accountFingerprint: "fp")
        }
        XCTAssertEqual(status(.success(auth(expiresIn: 3600))), .loggedIn)
        XCTAssertEqual(status(.success(auth(expiresIn: 0))), .loggedOut)
        XCTAssertEqual(status(.success(auth(expiresIn: -60))), .loggedOut)
        XCTAssertEqual(status(.failure(GrokAuthError.notFound)), .loggedOut)
        XCTAssertEqual(status(.failure(GrokAuthError.unreadable)), .unknown)
        XCTAssertEqual(status(.failure(GrokAuthError.malformed)), .unknown)
        XCTAssertEqual(status(.failure(GrokAuthError.ambiguous)), .unknown)
    }

    func testLocateUsesKnownPathsBeforeShellAndFallsBackToLoginShell() async {
        let expected = "/tmp/home/.local/bin/claude"
        let known = await CLITool.claude.locate(home: "/tmp/home", isExecutable: { $0 == expected }, shellLookup: { _ in
            XCTFail("Known path should avoid shell lookup")
            return nil
        })
        XCTAssertEqual(known?.path, expected)

        let fallback = await CLITool.codex.locate(home: "/tmp/home", isExecutable: { $0 == "/opt/test/codex" },
                                                   shellLookup: { name in
            XCTAssertEqual(name, "codex")
            return "/opt/test/codex\n"
        })
        XCTAssertEqual(fallback?.path, "/opt/test/codex")
        let bad = await CLITool.codex.locate(home: "/tmp/home", isExecutable: { _ in false },
                                              shellLookup: { _ in "not a path" })
        XCTAssertNil(bad)
    }

    func testOnlyStatesTheUserCanFixNeedAction() {
        let fixable: [SetupState] = [.cliMissing, .notLoggedIn, .loginTimedOut, .installFailed("x"),
                                     .binaryNotFound, .loginCheckFailed]
        let notFixable: [SetupState] = [.ready, .rateLimited(Date()), .readError("x"), .turnedOff,
                                        .installing, .waitingForSignIn, .readingUsage, .cancelled]
        for state in fixable { XCTAssertTrue(state.needsUserAction, "\(state)") }
        for state in notFixable { XCTAssertFalse(state.needsUserAction, "\(state)") }
    }
}
