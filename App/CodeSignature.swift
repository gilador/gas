import Foundation
import Security

enum CodeSignature {
    /// Ad-hoc / unsigned builds have no team identifier; several system services misbehave for them.
    static let isTeamSigned: Bool = {
        var codeRef: SecCode?
        guard SecCodeCopySelf(SecCSFlags(), &codeRef) == errSecSuccess, let codeRef else { return false }
        var staticRef: SecStaticCode?
        guard SecCodeCopyStaticCode(codeRef, SecCSFlags(), &staticRef) == errSecSuccess, let staticRef else { return false }
        var infoRef: CFDictionary?
        guard SecCodeCopySigningInformation(staticRef, SecCSFlags(rawValue: kSecCSSigningInformation), &infoRef) == errSecSuccess,
              let info = infoRef as? [String: Any] else { return false }
        return info[kSecCodeInfoTeamIdentifier as String] != nil
    }()

    /// The group container is only usable when the running code actually carries the App Groups entitlement.
    static func hasAppGroupEntitlement(_ group: String) -> Bool {
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(task, "com.apple.security.application-groups" as CFString, nil),
              let groups = value as? [String] else { return false }
        return groups.contains(group)
    }
}
