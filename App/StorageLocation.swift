import Foundation

enum StorageLocation {
    /// Without the App Groups entitlement, reading the group container blocks on a privacy prompt.
    static func containerURL(appGroupID: String) -> URL {
        let fm = FileManager.default
        if CodeSignature.hasAppGroupEntitlement(appGroupID),
           let group = fm.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            return group
        }
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Tokens", isDirectory: true)
        try? fm.createDirectory(at: support, withIntermediateDirectories: true)
        return support
    }
}
