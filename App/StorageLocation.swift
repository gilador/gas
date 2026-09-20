import Foundation

enum StorageLocation {
    /// The App Group container is only readable without a privacy prompt when the build is team-signed.
    static func containerURL(appGroupID: String) -> URL {
        let fm = FileManager.default
        if CodeSignature.isTeamSigned,
           let group = fm.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            return group
        }
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Tokens", isDirectory: true)
        try? fm.createDirectory(at: support, withIntermediateDirectories: true)
        return support
    }
}
