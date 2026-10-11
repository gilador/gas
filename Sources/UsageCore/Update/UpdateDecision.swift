import Foundation

public enum UpdateDecision: Equatable {
    case upToDate
    case available(ReleaseInfo)
    case skipped

    public static func decide(installed: AppVersion, latest: ReleaseInfo, skipped: AppVersion?) -> UpdateDecision {
        guard latest.version > installed else { return .upToDate }
        if let skipped, latest.version <= skipped { return .skipped }
        return .available(latest)
    }
}
