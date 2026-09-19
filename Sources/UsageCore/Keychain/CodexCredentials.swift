import Foundation

struct CodexCredentials: Decodable, Sendable {
    struct Tokens: Decodable, Sendable {
        let accessToken: String?
        let accountId: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case accountId = "account_id"
        }
    }

    let tokens: Tokens?

    static func parse(_ data: Data) throws -> CodexAuth {
        let credentials: CodexCredentials
        do {
            credentials = try JSONDecoder().decode(CodexCredentials.self, from: data)
        } catch {
            throw TokenReaderError.malformed
        }
        guard let token = credentials.tokens?.accessToken, !token.isEmpty else {
            throw TokenReaderError.notFound
        }
        return CodexAuth(accessToken: token,
                         accountID: credentials.tokens?.accountId,
                         expiresAt: JWTClaims.expiry(of: token))
    }
}

enum JWTClaims {
    static func expiry(of jwt: String) -> Date? {
        let parts = jwt.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = object["exp"] as? Double else { return nil }
        return Date(timeIntervalSince1970: exp)
    }
}
