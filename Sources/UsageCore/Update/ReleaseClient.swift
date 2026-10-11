import Foundation

public struct ReleaseInfo: Equatable, Sendable {
    public let version: AppVersion
    public let pageURL: URL
    public let pkgURL: URL
    public let checksumURL: URL
}

public enum ReleaseCheckError: Error, Equatable {
    case http(Int)
    case unreadable
    case noUsableRelease
}

public struct ReleaseClient: Sendable {
    public static let latestURL = URL(string: "https://api.github.com/repos/gilador/gas/releases/latest")!
    static let pagePrefix = "https://github.com/gilador/gas/"
    static let downloadPrefix = "https://github.com/gilador/gas/releases/download/"

    private let httpClient: UsageHTTPClient
    private let userAgent: String

    public init(httpClient: UsageHTTPClient, appVersion: String) {
        self.httpClient = httpClient
        self.userAgent = "gas/\(appVersion)"
    }

    public func latest() async throws -> ReleaseInfo {
        let (data, response) = try await httpClient.get(Self.latestURL, headers: [
            "Accept": "application/vnd.github+json",
            "User-Agent": userAgent
        ])
        guard response.statusCode == 200 else { throw ReleaseCheckError.http(response.statusCode) }
        return try Self.parse(data)
    }

    static func parse(_ data: Data) throws -> ReleaseInfo {
        guard let release = try? JSONDecoder().decode(GitHubRelease.self, from: data) else {
            throw ReleaseCheckError.unreadable
        }
        guard !release.draft, !release.prerelease, let version = AppVersion(release.tagName) else {
            throw ReleaseCheckError.noUsableRelease
        }
        let pkgName = "gas-\(version).pkg"
        func download(_ name: String) -> URL? {
            guard let asset = release.assets.first(where: { $0.name == name }),
                  asset.browserDownloadURL.hasPrefix(downloadPrefix) else { return nil }
            return URL(string: asset.browserDownloadURL)
        }
        guard release.htmlURL.hasPrefix(pagePrefix), let page = URL(string: release.htmlURL),
              let pkg = download(pkgName), let checksum = download(pkgName + ".sha256") else {
            throw ReleaseCheckError.noUsableRelease
        }
        return ReleaseInfo(version: version, pageURL: page, pkgURL: pkg, checksumURL: checksum)
    }
}

private struct GitHubRelease: Decodable {
    struct Asset: Decodable {
        let name: String
        let browserDownloadURL: String

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    let tagName: String
    let htmlURL: String
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case draft, prerelease, assets
    }
}
