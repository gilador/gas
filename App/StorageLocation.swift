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

    /// Always `~/Library/Application Support/Tokens`, even when the board lives in the App Group
    /// container, because the bash bridge (unsandboxed) writes there.
    static var bridgeDirectory: URL {
        let fm = FileManager.default
        let dir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Tokens", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
