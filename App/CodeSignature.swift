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
}
