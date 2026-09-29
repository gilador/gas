import Foundation

@MainActor
public protocol SetupRunningLogin {
    func terminate()
}

@MainActor
public protocol SetupRunner {
    func locate(_ tool: CLITool) async -> URL?
    func install(_ tool: CLITool) async -> ProcessOutput
    func startLogin(_ tool: CLITool, executable: URL) async -> (any SetupRunningLogin)?
    func checkLogin(_ tool: CLITool, executable: URL) async -> LoginStatus
    func sleepForStatusCheck() async
    func refresh(_ provider: ProviderID) async -> FetchStatus?
}

@MainActor
public final class SetupFlow {
    public var onChange: ((SetupState) -> Void)?
    public private(set) var state: SetupState = .readError("Waiting for first data…") {
        didSet { onChange?(state) }
    }

    private let tool: CLITool
    private let runner: any SetupRunner
    private let pollLimit: Int
    private var busy = false
    private var cancelled = false
    private var login: (any SetupRunningLogin)?

    public init(tool: CLITool, runner: any SetupRunner, pollLimit: Int = 150) {
        self.tool = tool
        self.runner = runner
        self.pollLimit = pollLimit
    }

    public func inspect(enabled: Bool, fetchStatus: FetchStatus?) async {
        guard !busy else { return }
        cancelled = false
        guard enabled else { state = .turnedOff; return }
        let found = await runner.locate(tool)
        guard !cancelled else { return }
        guard let executable = found else { state = .cliMissing; return }
        if fetchStatus == .ok {
            let loginStatus = await runner.checkLogin(tool, executable: executable)
            guard !cancelled else { return }
            state = loginStatus == .loggedOut ? .notLoggedIn : .ready
            return
        }
        switch fetchStatus {
        case .rateLimited, .error, .stale, .keychainDenied:
            state = .resolve(installed: true, loggedIn: nil, enabled: true, fetchStatus: fetchStatus)
        default:
            let loginStatus = await runner.checkLogin(tool, executable: executable)
            guard !cancelled else { return }
            switch loginStatus {
            case .loggedIn:
                state = .resolve(installed: true, loggedIn: true, enabled: true, fetchStatus: fetchStatus)
            case .loggedOut:
                state = .notLoggedIn
            case .unknown:
                state = fetchStatus == .needsSignIn ? .notLoggedIn : .loginCheckFailed
            }
        }
    }

    public func setUp() async {
        guard !busy else { return }
        busy = true
        cancelled = false
        defer { busy = false; stopLogin() }
        var executable = await runner.locate(tool)
        guard !cancelled else { return }
        if executable == nil {
            state = .installing
            let result = await runner.install(tool)
            UsageLog.note("setup \(tool.rawValue) install exit=\(result.exitCode.map(String.init) ?? "timeout")")
            guard !cancelled else { return }
            guard result.exitCode == 0 else {
                let last = result.output.split(whereSeparator: \.isNewline).last.map(String.init) ?? "unknown error"
                state = .installFailed(last)
                return
            }
            executable = await runner.locate(tool)
            guard !cancelled else { return }
            guard executable != nil else { state = .binaryNotFound; return }
        }
        guard let executable else { return }
        let initial = await runner.checkLogin(tool, executable: executable)
        UsageLog.note("setup \(tool.rawValue) login status=\(initial)")
        guard !cancelled else { return }
        switch initial {
        case .loggedIn:
            break
        case .unknown:
            state = .loginCheckFailed
            return
        case .loggedOut:
            state = .waitingForSignIn
            login = await runner.startLogin(tool, executable: executable)
            guard !cancelled else { return }
            guard login != nil else { state = .loginCheckFailed; return }
            var signedIn = false
            for _ in 0..<pollLimit {
                await runner.sleepForStatusCheck()
                guard !cancelled else { return }
                let status = await runner.checkLogin(tool, executable: executable)
                UsageLog.note("setup \(tool.rawValue) login status=\(status)")
                guard !cancelled else { return }
                if status == .loggedIn { signedIn = true; break }
                if status == .unknown { state = .loginCheckFailed; return }
            }
            guard signedIn else { state = .loginTimedOut; return }
        }
        stopLogin()
        state = .readingUsage
        let status = await runner.refresh(tool.provider)
        UsageLog.note("setup \(tool.rawValue) refresh status=\(statusName(status))")
        guard !cancelled else { return }
        state = .resolve(installed: true, loggedIn: true, enabled: true, fetchStatus: status)
    }

    public func tryAgain() async {
        guard !busy else { return }
        if case .installFailed = state { await setUp(); return }
        if state == .binaryNotFound { await setUp(); return }
        busy = true
        cancelled = false
        defer { busy = false }
        guard let executable = await runner.locate(tool) else { state = .cliMissing; return }
        guard !cancelled else { return }
        let status = await runner.checkLogin(tool, executable: executable)
        UsageLog.note("setup \(tool.rawValue) login status=\(status)")
        guard !cancelled else { return }
        guard status == .loggedIn else {
            state = status == .loggedOut ? .notLoggedIn : .loginCheckFailed
            return
        }
        state = .readingUsage
        let fetchStatus = await runner.refresh(tool.provider)
        UsageLog.note("setup \(tool.rawValue) refresh status=\(statusName(fetchStatus))")
        guard !cancelled else { return }
        state = .resolve(installed: true, loggedIn: true, enabled: true, fetchStatus: fetchStatus)
    }

    public func turnOff() {
        cancel()
        state = .turnedOff
    }

    public func cancel() {
        cancelled = true
        stopLogin()
        state = .cancelled
    }

    private func stopLogin() {
        login?.terminate()
        login = nil
    }

    private func statusName(_ status: FetchStatus?) -> String {
        switch status {
        case .ok: return "ok"
        case .stale: return "stale"
        case .needsSignIn: return "needsSignIn"
        case .keychainDenied: return "keychainDenied"
        case .error: return "error"
        case .rateLimited: return "rateLimited"
        case nil: return "missing"
        }
    }
}
