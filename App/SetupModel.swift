import AppKit
import Combine
import UsageCore

@MainActor
final class SetupModel: ObservableObject {
    @Published private(set) var rows: [ProviderID: SetupState] = [:]

    private let viewModel: UsageViewModel
    private var flows: [ProviderID: SetupFlow] = [:]

    init(viewModel: UsageViewModel) {
        self.viewModel = viewModel
        for tool in CLITool.allCases {
            let flow = SetupFlow(tool: tool, runner: AppSetupRunner(viewModel: viewModel))
            flow.onChange = { [weak self] state in self?.rows[tool.provider] = state }
            flows[tool.provider] = flow
        }
    }

    var needsAttention: Bool {
        ProviderID.displayOrder.contains { provider in
            ProviderSettings.isEnabled(provider) && rows[provider]?.needsUserAction == true
        }
    }

    func inspect() async {
        for provider in ProviderID.displayOrder {
            await flows[provider]?.inspect(enabled: ProviderSettings.isEnabled(provider),
                                           fetchStatus: viewModel.board.snapshot(for: provider)?.status)
        }
    }

    func setUp(_ provider: ProviderID) {
        Task { await flows[provider]?.setUp() }
    }

    func tryAgain(_ provider: ProviderID) {
        Task { await flows[provider]?.tryAgain() }
    }

    func dontUse(_ provider: ProviderID) {
        ProviderSettings.setEnabled(false, for: provider)
        flows[provider]?.turnOff()
    }

    func use(_ provider: ProviderID) {
        ProviderSettings.setEnabled(true, for: provider)
        Task {
            await viewModel.refresh(manual: true)
            await flows[provider]?.inspect(enabled: true,
                                           fetchStatus: viewModel.board.snapshot(for: provider)?.status)
        }
    }

    func cancel() {
        for flow in flows.values { flow.cancel() }
    }
}

@MainActor
private final class AppLoginProcess: SetupRunningLogin {
    private let process: Process

    init(_ process: Process) { self.process = process }

    func terminate() {
        if process.isRunning { process.terminate() }
    }
}

@MainActor
private struct AppSetupRunner: SetupRunner {
    let viewModel: UsageViewModel

    func locate(_ tool: CLITool) async -> URL? { await tool.locate() }

    func install(_ tool: CLITool) async -> ProcessOutput {
        let command = "set -o pipefail; /usr/bin/curl -fsSL \(tool.installerURL.absoluteString) | \(tool.installerShell)"
        return await ProcessRunner.run(executable: URL(fileURLWithPath: "/bin/zsh"),
                                       arguments: ["-c", command], timeout: 300, captureOutput: true)
    }

    func startLogin(_ tool: CLITool, executable: URL) async -> (any SetupRunningLogin)? {
        ProcessRunner.start(executable: executable, arguments: tool.loginArguments).map(AppLoginProcess.init)
    }

    func checkLogin(_ tool: CLITool, executable: URL) async -> LoginStatus {
        let result = await ProcessRunner.run(executable: executable, arguments: tool.statusArguments,
                                             timeout: 10, captureOutput: true)
        return tool.parseLoginStatus(output: result.output, exitCode: result.exitCode)
    }

    func sleepForStatusCheck() async {
        try? await Task.sleep(for: .seconds(2))
    }

    func refresh(_ provider: ProviderID) async -> FetchStatus? {
        await viewModel.refresh(manual: true)
        return viewModel.board.snapshot(for: provider)?.status
    }
}
