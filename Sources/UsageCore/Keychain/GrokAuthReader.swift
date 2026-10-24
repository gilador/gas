import CryptoKit
import Foundation

public struct GrokAuth: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    public let accessToken: String
    public let expiresAt: Date
    /// The account behind the token, so a token refresh keeps it and another account changes it.
    public let accountFingerprint: String

    public init(accessToken: String, expiresAt: Date, accountFingerprint: String) {
        self.accessToken = accessToken
        self.expiresAt = expiresAt
        self.accountFingerprint = accountFingerprint
    }

    public var description: String { "GrokAuth(expiresAt: \(expiresAt))" }
    public var debugDescription: String { description }
}

public enum GrokAuthError: Error, Equatable {
    case notFound
    case unreadable
    case malformed
    case ambiguous
}

public protocol GrokAuthReader: Sendable {
    func readGrokAuth() throws -> GrokAuth
}

public struct FileGrokAuthReader: GrokAuthReader {
    static let issuer = "https://auth.x.ai"
    static let clientID = "b1a00492-073a-47ea-816f-4c329264a828"
    static let entryKey = "\(issuer)::\(clientID)"
    static let maximumSize = 64 * 1024
    private static let retries = 2

    private let fileURL: URL
    private let retryDelay: TimeInterval

    public init(fileURL: URL = FileGrokAuthReader.defaultURL, retryDelay: TimeInterval = 0.05) {
        self.fileURL = fileURL
        self.retryDelay = retryDelay
    }

    public static var defaultURL: URL { defaultURL(environment: ProcessInfo.processInfo.environment) }

    public static func defaultURL(environment: [String: String]) -> URL {
        home(environment: environment).appendingPathComponent("auth.json")
    }

    static func home(environment: [String: String]) -> URL {
        environment["GROK_HOME"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".grok", isDirectory: true)
    }

    private enum Failure: Error {
        case transient(GrokAuthError)
        case final(GrokAuthError)
    }

    public func readGrokAuth() throws -> GrokAuth {
        var attempt = 0
        while true {
            do {
                return try GrokCredentials.parse(try readOnce())
            } catch Failure.final(let error) {
                throw error
            } catch Failure.transient(let error) {
                guard attempt < Self.retries else { throw error }
            } catch GrokAuthError.malformed {
                // The CLI may be mid-write, so a broken file gets the same short retry as a missing one.
                guard attempt < Self.retries else { throw GrokAuthError.malformed }
            }
            attempt += 1
            if retryDelay > 0 { Thread.sleep(forTimeInterval: retryDelay) }
        }
    }

    private func readOnce() throws -> Data {
        var info = stat()
        guard lstat(fileURL.path, &info) == 0 else {
            throw errno == ENOENT ? Failure.transient(.notFound) : Failure.final(.unreadable)
        }
        guard Self.isSafe(info) else { throw Failure.final(.unreadable) }

        let fd = open(fileURL.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else {
            throw errno == ENOENT ? Failure.transient(.unreadable) : Failure.final(.unreadable)
        }
        defer { close(fd) }
        var opened = stat()
        guard fstat(fd, &opened) == 0, Self.isSafe(opened) else { throw Failure.final(.unreadable) }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        while data.count <= Self.maximumSize {
            let count = read(fd, &buffer, buffer.count)
            if count < 0 {
                if errno == EINTR { continue }
                throw Failure.final(.unreadable)
            }
            if count == 0 { break }
            data.append(buffer, count: count)
        }
        guard data.count <= Self.maximumSize else { throw Failure.final(.unreadable) }
        guard !data.isEmpty else { throw Failure.transient(.unreadable) }
        return data
    }

    private static func isSafe(_ info: stat) -> Bool {
        (info.st_mode & S_IFMT) == S_IFREG
            && info.st_uid == getuid()
            && (info.st_mode & 0o077) == 0
            && info.st_size <= maximumSize
    }
}

enum GrokCredentials {
    private struct EntryKey: CodingKey {
        let stringValue: String
        init?(stringValue: String) { self.stringValue = stringValue }
        var intValue: Int? { nil }
        init?(intValue: Int) { nil }
    }

    private struct Entry: Decodable {
        let key: String?
        let expiresAt: String?
        let userID: String?

        enum CodingKeys: String, CodingKey {
            case key
            case expiresAt = "expires_at"
            case userID = "user_id"
        }
    }

    private struct Matches: Decodable {
        let entries: [Entry]

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: EntryKey.self)
            entries = try container.allKeys
                .filter { GrokCredentials.isGrokCLIEntry($0.stringValue) }
                .map { try container.decode(Entry.self, forKey: $0) }
        }
    }

    static func parse(_ data: Data) throws -> GrokAuth {
        let matches: Matches
        do {
            matches = try JSONDecoder().decode(Matches.self, from: data)
        } catch {
            throw GrokAuthError.malformed
        }
        guard let entry = matches.entries.first else { throw GrokAuthError.notFound }
        // The decoder keeps only the last of two identical keys, so count them in the raw text.
        guard matches.entries.count == 1, occurrences(of: "\"\(FileGrokAuthReader.entryKey)\"", in: data) <= 1 else {
            throw GrokAuthError.ambiguous
        }
        guard let key = entry.key, isHeaderSafe(key),
              let expiresAt = ClaudeDate.parse(entry.expiresAt) else { throw GrokAuthError.malformed }
        return GrokAuth(accessToken: key, expiresAt: expiresAt, accountFingerprint: fingerprint(userID: entry.userID))
    }

    static func isGrokCLIEntry(_ name: String) -> Bool {
        let parts = name.components(separatedBy: "::")
        guard parts.count == 2 else { return false }
        var issuer = parts[0].lowercased()
        while issuer.hasSuffix("/") { issuer.removeLast() }
        return issuer == FileGrokAuthReader.issuer && parts[1].lowercased() == FileGrokAuthReader.clientID
    }

    private static func isHeaderSafe(_ key: String) -> Bool {
        (1...4096).contains(key.utf8.count) && key.utf8.allSatisfy { (0x21...0x7E).contains($0) }
    }

    private static func fingerprint(userID: String?) -> String {
        let identity = "\(FileGrokAuthReader.entryKey)\n\(userID ?? "")"
        return SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func occurrences(of needle: String, in data: Data) -> Int {
        let pattern = Data(needle.utf8)
        var count = 0
        var start = data.startIndex
        while let found = data.range(of: pattern, in: start..<data.endIndex) {
            count += 1
            start = found.upperBound
        }
        return count
    }
}
