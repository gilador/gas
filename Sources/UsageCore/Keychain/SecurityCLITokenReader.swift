import Foundation

/// Reads Claude Code's token through /usr/bin/security. Claude Code writes the item with that tool,
/// so the item's access list always trusts it: no Keychain prompt, even after Claude Code rewrites
/// the item on a token refresh (which resets any "Always Allow" granted to other apps).
public struct SecurityCLITokenReader: TokenReader {
    public typealias Runner = @Sendable (_ executable: URL, _ arguments: [String]) throws -> (status: Int32, output: Data)

    private static let itemNotFound: Int32 = 44

    private let service: String
    private let account: String
    private let run: Runner

    public init(service: String = "Claude Code-credentials",
                account: String = NSUserName(),
                run: @escaping Runner = SecurityCLITokenReader.runProcess) {
        self.service = service
        self.account = account
        self.run = run
    }

    public func readClaudeToken() throws -> ClaudeToken {
        let result: (status: Int32, output: Data)
        do {
            result = try run(URL(fileURLWithPath: "/usr/bin/security"),
                             ["find-generic-password", "-s", service, "-a", account, "-w"])
        } catch {
            throw TokenReaderError.accessDenied
        }
        switch result.status {
        case 0: return try ClaudeCredentials.parse(result.output)
        case Self.itemNotFound: throw TokenReaderError.notFound
        default: throw TokenReaderError.accessDenied
        }
    }

    public static let runProcess: Runner = { executable, arguments in
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, data)
    }
}
