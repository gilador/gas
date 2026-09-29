import Foundation

public enum LoginStatus: Equatable {
    case loggedIn
    case loggedOut
    case unknown
}

public enum CLITool: String, CaseIterable {
    case claude
    case codex

    public var provider: ProviderID { self == .claude ? .claude : .openai }
    public var displayName: String { self == .claude ? "Claude Code" : "Codex CLI" }
    public var installerURL: URL {
        URL(string: self == .claude ? "https://claude.ai/install.sh" : "https://chatgpt.com/codex/install.sh")!
    }
    public var installerShell: String { self == .claude ? "/bin/bash" : "/bin/sh" }
    public var loginArguments: [String] {
        self == .claude ? ["auth", "login", "--claudeai"] : ["login"]
    }
    public var statusArguments: [String] {
        self == .claude ? ["auth", "status"] : ["login", "status"]
    }

    private func knownPaths(home: String) -> [String] {
        switch self {
        case .claude:
            return ["\(home)/.local/bin/claude", "\(home)/.claude/local/claude",
                    "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
        case .codex:
            return ["\(home)/.local/bin/codex", "/opt/homebrew/bin/codex", "/usr/local/bin/codex"]
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
        }
    }
}
