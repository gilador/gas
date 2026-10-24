import Foundation

public enum LoginStatus: Equatable {
    case loggedIn
    case loggedOut
    case unknown
}

public enum LoginCheck: Equatable {
    case command([String])
    case grokSignIn
}

public enum CLITool: String, CaseIterable {
    case claude
    case codex
    case grok

    public var provider: ProviderID {
        switch self {
        case .claude: return .claude
        case .codex: return .openai
        case .grok: return .xai
        }
    }

    public var displayName: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex: return "Codex CLI"
        case .grok: return "Grok CLI"
        }
    }

    public var installerURL: URL {
        switch self {
        case .claude: return URL(string: "https://claude.ai/install.sh")!
        case .codex: return URL(string: "https://chatgpt.com/codex/install.sh")!
        case .grok: return URL(string: "https://x.ai/cli/install.sh")!
        }
    }

    public var installerShell: String { self == .codex ? "/bin/sh" : "/bin/bash" }

    public var loginArguments: [String] {
        self == .claude ? ["auth", "login", "--claudeai"] : ["login"]
    }

    public var loginCheck: LoginCheck {
        switch self {
        case .claude: return .command(["auth", "status"])
        case .codex: return .command(["login", "status"])
        case .grok: return .grokSignIn
        }
    }

    private func knownPaths(home: String) -> [String] {
        switch self {
        case .claude:
            return ["\(home)/.local/bin/claude", "\(home)/.claude/local/claude",
                    "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
        case .codex:
            return ["\(home)/.local/bin/codex", "/opt/homebrew/bin/codex", "/usr/local/bin/codex"]
        case .grok:
            return ["\(home)/.grok/bin/grok"]
        }
    }

    public func locate(home: String, isExecutable: (String) -> Bool,
                       shellLookup: (String) async -> String?) async -> URL? {
        if let path = knownPaths(home: home).first(where: isExecutable) {
            return URL(fileURLWithPath: path)
        }
        guard let output = await shellLookup(rawValue),
              let path = output.split(whereSeparator: \.isNewline).map(String.init)
                .first(where: { $0.hasPrefix("/") && isExecutable($0) }) else { return nil }
        return URL(fileURLWithPath: path)
    }

    public func locate() async -> URL? {
        await locate(home: FileManager.default.homeDirectoryForCurrentUser.path,
                     isExecutable: { FileManager.default.isExecutableFile(atPath: $0) },
                     shellLookup: { name in
            let output = await ProcessRunner.run(executable: URL(fileURLWithPath: "/bin/zsh"),
                                                 arguments: ["-lc", "command -v \(name)"], timeout: 10,
                                                 captureOutput: true)
            return output.exitCode == 0 ? output.output : nil
        })
    }

    public func parseLoginStatus(output: String, exitCode: Int32?) -> LoginStatus {
        switch self {
        case .claude:
            guard exitCode == 0,
                  let data = output.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let loggedIn = json["loggedIn"] as? Bool else { return .unknown }
            return loggedIn ? .loggedIn : .loggedOut
        case .codex:
            switch exitCode {
            case 0: return .loggedIn
            case 1: return .loggedOut
            default: return .unknown
            }
        case .grok:
            return .unknown
        }
    }

    /// Grok's login status is read from its sign-in file, so setup never runs grok to ask.
    public static func grokLoginStatus(reader: GrokAuthReader, now: Date = Date()) -> LoginStatus {
        do {
            return try reader.readGrokAuth().expiresAt > now ? .loggedIn : .loggedOut
        } catch GrokAuthError.notFound {
            return .loggedOut
        } catch {
            return .unknown
        }
    }
}
