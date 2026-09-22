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
        let support = appSupport.appendingPathComponent("gas", isDirectory: true)
        let oldSupport = appSupport.appendingPathComponent("Tokens", isDirectory: true)
        let capitalizedSupport = appSupport.appendingPathComponent("Gas", isDirectory: true)
        // One-time moves from the app's previous names.
        if !fm.fileExists(atPath: support.path), fm.fileExists(atPath: oldSupport.path) {
            try? fm.moveItem(at: oldSupport, to: support)
        }
        if !fm.fileExists(atPath: support.path), fm.fileExists(atPath: capitalizedSupport.path) {
            try? fm.moveItem(at: capitalizedSupport, to: support)
        }
        try? fm.createDirectory(at: support, withIntermediateDirectories: true)
        return support
    }
}
