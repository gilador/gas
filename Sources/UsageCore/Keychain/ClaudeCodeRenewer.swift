import Foundation

public protocol TokenRenewer: Sendable {
    var isEnabled: Bool { get }
    func renew() async -> Bool
}

/// Lets Claude Code renew its own OAuth token with one small headless reply, so gas never writes the Keychain.
public struct ClaudeCodeRenewer: TokenRenewer {
    public typealias Runner = @Sendable (_ executable: URL, _ arguments: [String]) async -> Int32?

    public static let arguments = [
        "-p", "Reply with OK",
        "--model", "haiku",
        "--tools", "",
        "--no-session-persistence",
        "--strict-mcp-config",
        "--disable-slash-commands"
    ]
    /// An API key in Claude Code's settings would let the call succeed without a token renewal; this caps the spend.
    public static let minimumGap: TimeInterval = 60 * 60
    private static let timeout: TimeInterval = 90

    private let enabled: @Sendable () -> Bool
    private let locate: @Sendable () -> URL?
    private let run: Runner
    private let now: @Sendable () -> Date
    private let attempts = AttemptLog()

    public init(isEnabled: @escaping @Sendable () -> Bool = { true },
                locate: @escaping @Sendable () -> URL? = { ClaudeCodeRenewer.locateClaude() },
                run: @escaping Runner = ClaudeCodeRenewer.runProcess,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.enabled = isEnabled
        self.locate = locate
        self.run = run
        self.now = now
    }

    public var isEnabled: Bool { enabled() }

    public func renew() async -> Bool {
        guard attempts.claim(at: now(), gap: Self.minimumGap) else {
            UsageLog.note("claude renew skipped: last try less than 1 h ago")
            return false
        }
        guard let claude = locate() else {
            UsageLog.note("claude renew failed: claude not found")
            return false
        }
        let status = await run(claude, Self.arguments)
        UsageLog.note("claude renew exit=\(status.map(String.init) ?? "timeout")")
        return status == 0
    }

    public static func locateClaude() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["\(home)/.local/bin/claude", "\(home)/.claude/local/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    public static let runProcess: Runner = { executable, arguments in
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            process.currentDirectoryURL = FileManager.default.temporaryDirectory
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { finished in
                continuation.resume(returning: finished.terminationReason == .exit ? finished.terminationStatus : nil)
            }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: nil)
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if process.isRunning { process.terminate() }
            }
        }
    }
}

private final class AttemptLog: @unchecked Sendable {
    private let lock = NSLock()
    private var last: Date?

    func claim(at date: Date, gap: TimeInterval) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if let last, date.timeIntervalSince(last) < gap { return false }
        last = date
        return true
    }
}
