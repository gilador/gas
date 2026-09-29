import Foundation

public enum SetupStep: Equatable {
    case installing
    case waitingForSignIn
    case readingUsage
}

public enum SetupFailure: Equatable {
    case installFailed(String)
    case binaryNotFound
    case loginTimedOut
    case loginCheckFailed
}

public enum SetupState: Equatable {
    case ready
    case cliMissing
    case notLoggedIn
    case rateLimited(Date)
    case readError(String)
    case turnedOff
    case installing
    case waitingForSignIn
    case readingUsage
    case installFailed(String)
    case binaryNotFound
    case loginTimedOut
    case loginCheckFailed
    case cancelled

    /// States the user can fix in the setup window; the first launch opens the window only for these.
    public var needsUserAction: Bool {
        switch self {
        case .cliMissing, .notLoggedIn, .loginTimedOut, .installFailed, .binaryNotFound, .loginCheckFailed:
            return true
        case .ready, .rateLimited, .readError, .turnedOff, .installing, .waitingForSignIn, .readingUsage, .cancelled:
            return false
        }
    }

    public static func resolve(installed: Bool, loggedIn: Bool?, enabled: Bool,
                               fetchStatus: FetchStatus?, step: SetupStep? = nil,
                               failure: SetupFailure? = nil) -> SetupState {
        if !enabled { return .turnedOff }
        if let step {
            switch step {
            case .installing: return .installing
            case .waitingForSignIn: return .waitingForSignIn
            case .readingUsage: return .readingUsage
            }
        }
        if let failure {
            switch failure {
            case .installFailed(let message): return .installFailed(message)
            case .binaryNotFound: return .binaryNotFound
            case .loginTimedOut: return .loginTimedOut
            case .loginCheckFailed: return .loginCheckFailed
            }
        }
        if !installed { return .cliMissing }
        if case .rateLimited(let until, _) = fetchStatus { return .rateLimited(until) }
        if case .error(let message) = fetchStatus { return .readError(message) }
        if case .stale(let reason) = fetchStatus { return .readError(reason) }
        if case .keychainDenied = fetchStatus { return .readError("Keychain access denied") }
        if loggedIn == false || fetchStatus == .needsSignIn { return .notLoggedIn }
        if loggedIn == true && fetchStatus == .ok { return .ready }
        return .readError("Waiting for first data…")
    }
}
