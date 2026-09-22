import Foundation

enum StorageLocation {
    /// Without the App Groups entitlement, reading the group container blocks on a privacy prompt.
    static func containerURL(appGroupID: String) -> URL {
        let fm = FileManager.default
        if CodeSignature.hasAppGroupEntitlement(appGroupID),
           let group = fm.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            return group
        }
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let support = appSupport.appendingPathComponent("Gas", isDirectory: true)
        let oldSupport = appSupport.appendingPathComponent("Tokens", isDirectory: true)
        // One-time move from the app's previous name.
        if !fm.fileExists(atPath: support.path), fm.fileExists(atPath: oldSupport.path) {
            try? fm.moveItem(at: oldSupport, to: support)
        }
        try? fm.createDirectory(at: support, withIntermediateDirectories: true)
        return support
    }
}
