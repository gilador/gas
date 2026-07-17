import Foundation
import Security

public struct KeychainTokenReader: TokenReader {
    private let service: String
    private let account: String

    public init(service: String = "Claude Code-credentials",
                account: String = NSUserName()) {
        self.service = service
        self.account = account
    }

    public func readClaudeToken() throws -> ClaudeToken {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { throw TokenReaderError.malformed }
            return try ClaudeCredentials.parse(data)
        case errSecItemNotFound:
            throw TokenReaderError.notFound
        case errSecAuthFailed, errSecInteractionNotAllowed, errSecUserCanceled:
            throw TokenReaderError.accessDenied
        default:
            throw TokenReaderError.accessDenied
        }
    }
}
