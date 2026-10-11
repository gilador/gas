import CryptoKit
import Foundation

public enum UpdateDownloadError: Error, Equatable {
    case download(String)
    case checksumMissing
    case checksumMismatch
}

public struct UpdateDownloader: Sendable {
    public typealias Fetch = @Sendable (URL) async throws -> Data

    private let directory: URL
    private let fetch: Fetch

    public init(directory: URL, fetch: @escaping Fetch = UpdateDownloader.urlSessionFetch) {
        self.directory = directory
        self.fetch = fetch
    }

    /// Saves the pkg only after its SHA-256 matches the release's checksum file, so a bad download is never opened.
    public func download(_ release: ReleaseInfo) async throws -> URL {
        let fileName = release.pkgURL.lastPathComponent
        guard let checksumData = try? await fetch(release.checksumURL),
              let expected = Self.parseChecksum(checksumData, fileName: fileName) else {
            throw UpdateDownloadError.checksumMissing
        }
        let pkg: Data
        do {
            pkg = try await fetch(release.pkgURL)
        } catch {
            throw UpdateDownloadError.download(error.localizedDescription)
        }
        guard Self.sha256Hex(pkg) == expected else { throw UpdateDownloadError.checksumMismatch }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(fileName)
        try pkg.write(to: destination, options: .atomic)
        return destination
    }

    static func parseChecksum(_ data: Data, fileName: String) -> String? {
        guard let line = String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline).first else {
            return nil
        }
        let fields = line.split(whereSeparator: \.isWhitespace)
        guard let digest = fields.first?.lowercased(), digest.count == 64, digest.allSatisfy(\.isHexDigit) else {
            return nil
        }
        if fields.count > 1 {
            let name = fields[1].hasPrefix("*") ? String(fields[1].dropFirst()) : String(fields[1])
            guard name == fileName else { return nil }
        }
        return digest
    }

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public static let urlSessionFetch: Fetch = { url in
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}
