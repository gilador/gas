# Over-the-air Updates Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** gas checks the public GitHub repo for a newer release and, after one click, downloads the pkg, checks its SHA-256, and opens it in the Installer.

**Architecture:**
- **UsageCore** gets four small units with no UI. They are fully unit-tested: `AppVersion`, `ReleaseClient`, `UpdateDecision` and `UpdateDownloader`.
- **The app** gets `UpdateModel.shared`, which holds the timer, the state and the actions. It also gets an `UpdateBanner` in the menu, a dot on the menu bar label and on the floating panel, and an "Updates" section in Settings.
- **Release scripts:** `package.sh` writes a checksum file, and the new `publish.sh` creates the GitHub release.

**Tech Stack:** Swift 5.9, SwiftUI and AppKit, CryptoKit, URLSession, XCTest, XcodeGen, bash, and `gh`.

**Spec:** `docs/superpowers/specs/2026-10-12-ota-updates-design.md`

## Global Constraints

- **Versions:** macOS 14 deployment target, Swift tools 5.9. No new dependencies (only Foundation, CryptoKit, AppKit and SwiftUI).
- **Release API:** `https://api.github.com/repos/gilador/gas/releases/latest`, with the headers `Accept: application/vnd.github+json` and `User-Agent: gas/<version>`.
- **Downloads:** accept only URLs that start with `https://github.com/gilador/gas/releases/download/`. The release page URL must start with `https://github.com/gilador/gas/`.
- **Assets:** `gas-<version>.pkg` and `gas-<version>.pkg.sha256`, where the checksum file is in `shasum -a 256` format: the hex digest, two spaces, then the file name.
- **UserDefaults keys:** `checkForUpdates` (Bool, default true) and `skippedUpdateVersion` (String).
- **Schedule:** the first check 60 s after launch, then every 6 h, only while `checkForUpdates` is true.
- **Cache folder:** `~/Library/Caches/com.gilad.agentusage/updates/`.
- **Menu texts:** "gas <version> is available", with the buttons "Update" and "Later"; "Downloading gas <version>…"; "Update failed: <reason>", with the buttons "Try again" and "Open release page".
- **Settings texts:** "Check for updates automatically", "Check for updates", "Up to date (<version>)", "Checking…", "Couldn't check: <reason>".
- **Skips:** a manual check ignores the skipped version. An automatic check hides a version that is not higher than the skipped one.
- **Code style:** no comments, except a one-line WHY. Match the code around it.
- **Commits:** `feat(update): …` or `build: …`, ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- **Editing in this repo:** the Edit and Write tools are blocked by an old worktree hook. Edit with Bash (python or heredocs). Write new files to the scratchpad and copy them into the repo with `cp`.

## Review Focus

1. **GitHub has no release yet, or answers 404 or 403 (rate limit).** The automatic check stays silent. A manual check shows "Couldn't check: GitHub answered HTTP 404". The test for this is in Task 2.
2. **A tag that is not a plain version** (for example "v1.0.25-beta" or "nightly"). It is ignored as "no usable release", with no crash. The tests are in Tasks 1 and 2.
3. **A checksum file with uppercase hex, a CRLF line end, or the `*` binary marker.** It is accepted. A checksum for a different file name is rejected. The test is in Task 4.
4. **The user clicks Update twice.** Only one download runs, because of the phase guard in `UpdateModel.update()` in Task 5. The app layer has no unit tests, so this is checked by reading the code.
5. **"1.0" and "1.0.0" are equal.** This prevents a loop where gas always says an update is available. The test is in Task 1.

---

### Task 1: AppVersion

**Files:**
- Create: `Sources/UsageCore/Update/AppVersion.swift`
- Test: `Tests/UsageCoreTests/AppVersionTests.swift`

**Interfaces:**
- Produces:
  - `public struct AppVersion: Comparable, Hashable, Sendable, CustomStringConvertible`
  - `public init?(_ text: String)`
  - `public let parts: [Int]`
  - `description`, for example `"1.0.24"`, without the "v"

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import UsageCore

final class AppVersionTests: XCTestCase {
    func testParsesWithAndWithoutPrefix() {
        XCTAssertEqual(AppVersion("v1.0.24")?.parts, [1, 0, 24])
        XCTAssertEqual(AppVersion("1.0.24")?.parts, [1, 0, 24])
        XCTAssertEqual(AppVersion(" V2.1 \n")?.parts, [2, 1])
    }

    func testComparesNumbersNotText() {
        XCTAssertLessThan(AppVersion("1.0.9")!, AppVersion("1.0.10")!)
        XCTAssertLessThan(AppVersion("1.9.9")!, AppVersion("2.0")!)
        XCTAssertFalse(AppVersion("1.0.24")! < AppVersion("1.0.24")!)
    }

    func testMissingPartsCountAsZero() {
        XCTAssertEqual(AppVersion("1.0")!, AppVersion("1.0.0")!)
        XCTAssertEqual(Set([AppVersion("1.0")!, AppVersion("1.0.0")!]).count, 1)
        XCTAssertFalse(AppVersion("1.0")! < AppVersion("1.0.0")!)
    }

    func testRejectsBadInput() {
        for text in ["", "v", "1..2", "1.0.24-beta", "nightly", "1.0.0.0.1", "1.-2", "1.0.٣"] {
            XCTAssertNil(AppVersion(text), text)
        }
    }

    func testDescriptionDropsThePrefix() {
        XCTAssertEqual(AppVersion("v1.0.24")?.description, "1.0.24")
    }
}
```

- [ ] **Step 2: Run the test and make sure it fails**

Run: `swift test --filter AppVersionTests`
Expected: FAIL, with the compile error "cannot find 'AppVersion' in scope".

- [ ] **Step 3: Write the code**

```swift
import Foundation

public struct AppVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
    public let parts: [Int]

    public init?(_ text: String) {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.first == "v" || trimmed.first == "V" { trimmed.removeFirst() }
        let pieces = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...4).contains(pieces.count) else { return nil }
        var numbers: [Int] = []
        for piece in pieces {
            guard !piece.isEmpty, piece.allSatisfy({ $0.isASCII && $0.isNumber }), let value = Int(piece) else {
                return nil
            }
            numbers.append(value)
        }
        parts = numbers
    }

    public var description: String { parts.map(String.init).joined(separator: ".") }

    private var normalized: [Int] {
        var trimmed = parts
        while trimmed.count > 1, trimmed.last == 0 { trimmed.removeLast() }
        return trimmed
    }

    public static func == (lhs: AppVersion, rhs: AppVersion) -> Bool { lhs.normalized == rhs.normalized }

    public func hash(into hasher: inout Hasher) { hasher.combine(normalized) }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        for index in 0..<max(lhs.parts.count, rhs.parts.count) {
            let left = index < lhs.parts.count ? lhs.parts[index] : 0
            let right = index < rhs.parts.count ? rhs.parts[index] : 0
            if left != right { return left < right }
        }
        return false
    }
}
```

- [ ] **Step 4: Run the tests and make sure they pass**

Run: `swift test --filter AppVersionTests`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/UsageCore/Update/AppVersion.swift Tests/UsageCoreTests/AppVersionTests.swift
git commit -m "feat(update): AppVersion parses and compares release versions

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: ReleaseClient

**Files:**
- Create: `Sources/UsageCore/Update/ReleaseClient.swift`
- Create: `Tests/UsageCoreTests/Fixtures/github_release.json`
- Test: `Tests/UsageCoreTests/ReleaseClientTests.swift`

**Interfaces:**
- Consumes:
  - `AppVersion` (Task 1)
  - `UsageHTTPClient` (existing: `func get(_ url: URL, headers: [String: String]) async throws -> (Data, HTTPURLResponse)`)
  - `SpyHTTPClient` (existing test stub: `init(data:statusCode:responseHeaders:)` and `calls: [Call]`, where `Call` has `url` and `headers`)
- Produces:
  - `public struct ReleaseInfo: Equatable, Sendable { version: AppVersion; pageURL, pkgURL, checksumURL: URL }`. The memberwise init is internal.
  - `public enum ReleaseCheckError: Error, Equatable { case http(Int), unreadable, noUsableRelease }`
  - `public struct ReleaseClient: Sendable { public init(httpClient: UsageHTTPClient, appVersion: String); public func latest() async throws -> ReleaseInfo; static func parse(_ data: Data) throws -> ReleaseInfo }`

- [ ] **Step 1: Write the fixture**

`Tests/UsageCoreTests/Fixtures/github_release.json`:

```json
{
  "tag_name": "v1.0.24",
  "html_url": "https://github.com/gilador/gas/releases/tag/v1.0.24",
  "draft": false,
  "prerelease": false,
  "assets": [
    {"name": "gas-1.0.24.dmg", "browser_download_url": "https://github.com/gilador/gas/releases/download/v1.0.24/gas-1.0.24.dmg"},
    {"name": "gas-1.0.24.pkg", "browser_download_url": "https://github.com/gilador/gas/releases/download/v1.0.24/gas-1.0.24.pkg"},
    {"name": "gas-1.0.24.pkg.sha256", "browser_download_url": "https://github.com/gilador/gas/releases/download/v1.0.24/gas-1.0.24.pkg.sha256"}
  ]
}
```

- [ ] **Step 2: Write the failing test**

```swift
import XCTest
@testable import UsageCore

final class ReleaseClientTests: XCTestCase {
    private func release(_ change: (inout [String: Any]) -> Void = { _ in }) throws -> Data {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Fixtures.data("github_release")) as? [String: Any])
        change(&json)
        return try JSONSerialization.data(withJSONObject: json)
    }

    private func setAsset(_ name: String, url: String?, in json: inout [String: Any]) {
        var assets = json["assets"] as? [[String: Any]] ?? []
        assets.removeAll { $0["name"] as? String == name }
        if let url { assets.append(["name": name, "browser_download_url": url]) }
        json["assets"] = assets
    }

    func testParsesTheLatestRelease() throws {
        let info = try ReleaseClient.parse(release())
        XCTAssertEqual(info.version, AppVersion("1.0.24"))
        XCTAssertEqual(info.pageURL.absoluteString, "https://github.com/gilador/gas/releases/tag/v1.0.24")
        XCTAssertEqual(info.pkgURL.absoluteString, "https://github.com/gilador/gas/releases/download/v1.0.24/gas-1.0.24.pkg")
        XCTAssertEqual(info.checksumURL.absoluteString, "https://github.com/gilador/gas/releases/download/v1.0.24/gas-1.0.24.pkg.sha256")
    }

    func testDraftsAndPrereleasesAreIgnored() throws {
        XCTAssertThrowsError(try ReleaseClient.parse(release { $0["draft"] = true })) {
            XCTAssertEqual($0 as? ReleaseCheckError, .noUsableRelease)
        }
        XCTAssertThrowsError(try ReleaseClient.parse(release { $0["prerelease"] = true })) {
            XCTAssertEqual($0 as? ReleaseCheckError, .noUsableRelease)
        }
    }

    func testAReleaseWithoutAChecksumIsUnusable() throws {
        let data = try release { self.setAsset("gas-1.0.24.pkg.sha256", url: nil, in: &$0) }
        XCTAssertThrowsError(try ReleaseClient.parse(data)) {
            XCTAssertEqual($0 as? ReleaseCheckError, .noUsableRelease)
        }
    }

    func testRejectsDownloadsFromOtherReposOrPlainHTTP() throws {
        for url in ["https://github.com/someone/gas/releases/download/v1.0.24/gas-1.0.24.pkg",
                    "http://github.com/gilador/gas/releases/download/v1.0.24/gas-1.0.24.pkg"] {
            let data = try release { self.setAsset("gas-1.0.24.pkg", url: url, in: &$0) }
            XCTAssertThrowsError(try ReleaseClient.parse(data), url) {
                XCTAssertEqual($0 as? ReleaseCheckError, .noUsableRelease)
            }
        }
    }

    func testATagThatIsNotAVersionIsUnusable() throws {
        for tag in ["nightly", "v1.0.25-beta"] {
            XCTAssertThrowsError(try ReleaseClient.parse(release { $0["tag_name"] = tag }), tag) {
                XCTAssertEqual($0 as? ReleaseCheckError, .noUsableRelease)
            }
        }
    }

    func testBadJSONIsUnreadable() {
        XCTAssertThrowsError(try ReleaseClient.parse(Data("not json".utf8))) {
            XCTAssertEqual($0 as? ReleaseCheckError, .unreadable)
        }
    }

    func testLatestSendsTheHeadersAndReturnsTheRelease() async throws {
        let spy = SpyHTTPClient(data: try Fixtures.data("github_release"), statusCode: 200)
        let info = try await ReleaseClient(httpClient: spy, appVersion: "1.0.23").latest()
        XCTAssertEqual(info.version, AppVersion("1.0.24"))
        XCTAssertEqual(spy.calls.first?.url, ReleaseClient.latestURL)
        XCTAssertEqual(spy.calls.first?.headers["Accept"], "application/vnd.github+json")
        XCTAssertEqual(spy.calls.first?.headers["User-Agent"], "gas/1.0.23")
    }

    func testLatestMapsHTTPErrors() async {
        for status in [403, 404] {
            do {
                _ = try await ReleaseClient(httpClient: SpyHTTPClient(statusCode: status), appVersion: "1.0.23").latest()
                XCTFail("expected an error for \(status)")
            } catch {
                XCTAssertEqual(error as? ReleaseCheckError, .http(status))
            }
        }
    }
}
```

- [ ] **Step 3: Run the test and make sure it fails**

Run: `swift test --filter ReleaseClientTests`
Expected: FAIL, with the compile error "cannot find 'ReleaseClient' in scope".

- [ ] **Step 4: Write the code**

```swift
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
```

- [ ] **Step 5: Run the tests and make sure they pass**

Run: `swift test --filter ReleaseClientTests`
Expected: PASS (8 tests).

- [ ] **Step 6: Commit**

```bash
git add Sources/UsageCore/Update/ReleaseClient.swift Tests/UsageCoreTests/Fixtures/github_release.json Tests/UsageCoreTests/ReleaseClientTests.swift
git commit -m "feat(update): ReleaseClient reads the latest GitHub release and accepts only this repo's assets

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: UpdateDecision

**Files:**
- Create: `Sources/UsageCore/Update/UpdateDecision.swift`
- Test: `Tests/UsageCoreTests/UpdateDecisionTests.swift`

**Interfaces:**
- Consumes: `AppVersion` (Task 1) and `ReleaseInfo` (Task 2).
- Produces: `public enum UpdateDecision: Equatable { case upToDate, available(ReleaseInfo), skipped; public static func decide(installed: AppVersion, latest: ReleaseInfo, skipped: AppVersion?) -> UpdateDecision }`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import UsageCore

final class UpdateDecisionTests: XCTestCase {
    private func info(_ version: String) -> ReleaseInfo {
        ReleaseInfo(version: AppVersion(version)!,
                    pageURL: URL(string: "https://github.com/gilador/gas/releases/tag/v\(version)")!,
                    pkgURL: URL(string: "https://github.com/gilador/gas/releases/download/v\(version)/gas-\(version).pkg")!,
                    checksumURL: URL(string: "https://github.com/gilador/gas/releases/download/v\(version)/gas-\(version).pkg.sha256")!)
    }

    func testSameOrOlderReleaseIsUpToDate() {
        XCTAssertEqual(UpdateDecision.decide(installed: AppVersion("1.0.24")!, latest: info("1.0.24"), skipped: nil), .upToDate)
        XCTAssertEqual(UpdateDecision.decide(installed: AppVersion("1.0.25")!, latest: info("1.0.24"), skipped: nil), .upToDate)
    }

    func testNewerReleaseIsAvailable() {
        XCTAssertEqual(UpdateDecision.decide(installed: AppVersion("1.0.23")!, latest: info("1.0.24"), skipped: nil),
                       .available(info("1.0.24")))
    }

    func testASkippedVersionStaysHidden() {
        XCTAssertEqual(UpdateDecision.decide(installed: AppVersion("1.0.23")!, latest: info("1.0.24"),
                                             skipped: AppVersion("1.0.24")), .skipped)
    }

    func testANewerReleaseAfterASkipShowsAgain() {
        XCTAssertEqual(UpdateDecision.decide(installed: AppVersion("1.0.23")!, latest: info("1.0.25"),
                                             skipped: AppVersion("1.0.24")), .available(info("1.0.25")))
    }
}
```

- [ ] **Step 2: Run the test and make sure it fails**

Run: `swift test --filter UpdateDecisionTests`
Expected: FAIL, with the compile error "cannot find 'UpdateDecision' in scope".

- [ ] **Step 3: Write the code**

```swift
import Foundation

public enum UpdateDecision: Equatable {
    case upToDate
    case available(ReleaseInfo)
    case skipped

    public static func decide(installed: AppVersion, latest: ReleaseInfo, skipped: AppVersion?) -> UpdateDecision {
        guard latest.version > installed else { return .upToDate }
        if let skipped, latest.version <= skipped { return .skipped }
        return .available(latest)
    }
}
```

- [ ] **Step 4: Run the tests and make sure they pass**

Run: `swift test --filter UpdateDecisionTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/UsageCore/Update/UpdateDecision.swift Tests/UsageCoreTests/UpdateDecisionTests.swift
git commit -m "feat(update): UpdateDecision with skip support

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: UpdateDownloader

**Files:**
- Create: `Sources/UsageCore/Update/UpdateDownloader.swift`
- Test: `Tests/UsageCoreTests/UpdateDownloaderTests.swift`

**Interfaces:**
- Consumes: `ReleaseInfo` (Task 2).
- Produces:
  - `public enum UpdateDownloadError: Error, Equatable { case download(String), checksumMissing, checksumMismatch }`
  - `public struct UpdateDownloader: Sendable { public typealias Fetch = @Sendable (URL) async throws -> Data; public init(directory: URL, fetch: @escaping Fetch = UpdateDownloader.urlSessionFetch); public func download(_ release: ReleaseInfo) async throws -> URL }`
  - Internal: `static func parseChecksum(_ data: Data, fileName: String) -> String?` and `static func sha256Hex(_ data: Data) -> String`

- [ ] **Step 1: Write the failing test**

```swift
import CryptoKit
import XCTest
@testable import UsageCore

final class UpdateDownloaderTests: XCTestCase {
    private let release = ReleaseInfo(
        version: AppVersion("1.0.24")!,
        pageURL: URL(string: "https://github.com/gilador/gas/releases/tag/v1.0.24")!,
        pkgURL: URL(string: "https://github.com/gilador/gas/releases/download/v1.0.24/gas-1.0.24.pkg")!,
        checksumURL: URL(string: "https://github.com/gilador/gas/releases/download/v1.0.24/gas-1.0.24.pkg.sha256")!)
    private let pkg = Data("installer bytes".utf8)

    private var digest: String { SHA256.hash(data: pkg).map { String(format: "%02x", $0) }.joined() }

    private func downloader(pkg: Data?, checksum: String?) -> (UpdateDownloader, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let release = release
        let downloader = UpdateDownloader(directory: directory) { url in
            if url == release.pkgURL, let pkg { return pkg }
            if url == release.checksumURL, let checksum { return Data(checksum.utf8) }
            throw URLError(.fileDoesNotExist)
        }
        return (downloader, directory)
    }

    func testAMatchingChecksumSavesThePkg() async throws {
        let (downloader, directory) = downloader(pkg: pkg, checksum: "\(digest)  gas-1.0.24.pkg\n")
        let file = try await downloader.download(release)
        XCTAssertEqual(file, directory.appendingPathComponent("gas-1.0.24.pkg"))
        XCTAssertEqual(try Data(contentsOf: file), pkg)
    }

    func testAMismatchThrowsAndSavesNothing() async {
        let (downloader, directory) = downloader(pkg: Data("tampered".utf8), checksum: "\(digest)  gas-1.0.24.pkg\n")
        do {
            _ = try await downloader.download(release)
            XCTFail("expected a checksum mismatch")
        } catch {
            XCTAssertEqual(error as? UpdateDownloadError, .checksumMismatch)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("gas-1.0.24.pkg").path))
    }

    func testAMissingChecksumFileThrows() async {
        let (downloader, _) = downloader(pkg: pkg, checksum: nil)
        do {
            _ = try await downloader.download(release)
            XCTFail("expected a missing checksum")
        } catch {
            XCTAssertEqual(error as? UpdateDownloadError, .checksumMissing)
        }
    }

    func testABadChecksumFileThrows() async {
        let (downloader, _) = downloader(pkg: pkg, checksum: "hello")
        do {
            _ = try await downloader.download(release)
            XCTFail("expected a missing checksum")
        } catch {
            XCTAssertEqual(error as? UpdateDownloadError, .checksumMissing)
        }
    }

    func testAFailedPkgDownloadThrows() async {
        let (downloader, _) = downloader(pkg: nil, checksum: "\(digest)  gas-1.0.24.pkg\n")
        do {
            _ = try await downloader.download(release)
            XCTFail("expected a download error")
        } catch {
            guard case .download = error as? UpdateDownloadError else { return XCTFail("got \(error)") }
        }
    }

    func testTheChecksumParserAcceptsUppercaseCRLFAndTheBinaryMarker() {
        let text = "\(digest.uppercased()) *gas-1.0.24.pkg\r\n"
        XCTAssertEqual(UpdateDownloader.parseChecksum(Data(text.utf8), fileName: "gas-1.0.24.pkg"), digest)
        XCTAssertEqual(UpdateDownloader.parseChecksum(Data(digest.utf8), fileName: "gas-1.0.24.pkg"), digest)
    }

    func testAChecksumForAnotherFileIsRejected() {
        let text = "\(digest)  gas-1.0.23.pkg\n"
        XCTAssertNil(UpdateDownloader.parseChecksum(Data(text.utf8), fileName: "gas-1.0.24.pkg"))
    }
}
```

- [ ] **Step 2: Run the test and make sure it fails**

Run: `swift test --filter UpdateDownloaderTests`
Expected: FAIL, with the compile error "cannot find 'UpdateDownloader' in scope".

- [ ] **Step 3: Write the code**

```swift
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
```

- [ ] **Step 4: Run the tests and make sure they pass**

Run: `swift test --filter UpdateDownloaderTests`
Expected: PASS (7 tests). Then run `swift test`: all tests pass (267 existing tests plus 24 new ones).

- [ ] **Step 5: Commit**

```bash
git add Sources/UsageCore/Update/UpdateDownloader.swift Tests/UsageCoreTests/UpdateDownloaderTests.swift
git commit -m "feat(update): UpdateDownloader keeps a pkg only when its SHA-256 matches the release checksum

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: UpdateModel in the app

**Files:**
- Modify: `Sources/UsageCore/Network/UsageLog.swift`: make `static func note(_ line: String)` public.
- Create: `App/UpdateModel.swift`
- Modify: `App/AppDelegate.swift`: call `UpdateModel.shared.start()` right after `self.viewModel = viewModel`.

**Interfaces:**
- Consumes:
  - `ReleaseClient`, `UpdateDecision`, `UpdateDownloader`, `ReleaseCheckError`, `UpdateDownloadError` and `AppVersion` (Tasks 1–4)
  - `URLSessionHTTPClient` (existing, public)
- Produces:
  - `@MainActor final class UpdateModel: ObservableObject`, with `static let shared`, `static let autoCheckKey = "checkForUpdates"` and `static let skippedKey = "skippedUpdateVersion"`
  - `enum Phase: Equatable { idle, checking, upToDate, checkFailed(String), available(ReleaseInfo), downloading(ReleaseInfo), failed(ReleaseInfo, String) }`
  - `@Published private(set) var phase` and `let installed: AppVersion?`
  - `var showsDot: Bool` and `func start()`
  - `func check(manual: Bool) async`, `func update() async`, `func later()` and `func openReleasePage()`

- [ ] **Step 1: Make `UsageLog.note` public**

In `Sources/UsageCore/Network/UsageLog.swift`, change `static func note(_ line: String) { record(line) }` to `public static func note(_ line: String) { record(line) }`.

- [ ] **Step 2: Write `App/UpdateModel.swift`**

```swift
import AppKit
import Combine
import UsageCore

@MainActor
final class UpdateModel: ObservableObject {
    static let shared = UpdateModel()
    static let autoCheckKey = "checkForUpdates"
    static let skippedKey = "skippedUpdateVersion"

    enum Phase: Equatable {
        case idle
        case checking
        case upToDate
        case checkFailed(String)
        case available(ReleaseInfo)
        case downloading(ReleaseInfo)
        case failed(ReleaseInfo, String)
    }

    @Published private(set) var phase: Phase = .idle

    let installed: AppVersion?
    private let client: ReleaseClient
    private let downloader: UpdateDownloader
    private var timer: Timer?

    init() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        installed = AppVersion(version)
        client = ReleaseClient(httpClient: URLSessionHTTPClient(), appVersion: version)
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        downloader = UpdateDownloader(directory: caches.appendingPathComponent("com.gilad.agentusage/updates", isDirectory: true))
    }

    var showsDot: Bool {
        switch phase {
        case .available, .downloading, .failed: return true
        case .idle, .checking, .upToDate, .checkFailed: return false
        }
    }

    static var autoCheckEnabled: Bool {
        UserDefaults.standard.object(forKey: autoCheckKey) as? Bool ?? true
    }

    func start() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in
            Task { @MainActor in await self?.check(manual: false) }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 60 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.check(manual: false) }
        }
    }

    func check(manual: Bool) async {
        guard manual || Self.autoCheckEnabled, let installed else { return }
        switch phase {
        case .checking, .downloading: return
        default: break
        }
        if manual { phase = .checking }
        do {
            let latest = try await client.latest()
            UsageLog.note("update check latest=\(latest.version) installed=\(installed)")
            let skipped = manual ? nil : UserDefaults.standard.string(forKey: Self.skippedKey).flatMap(AppVersion.init)
            switch UpdateDecision.decide(installed: installed, latest: latest, skipped: skipped) {
            case .available(let release): phase = .available(release)
            case .upToDate, .skipped: phase = manual ? .upToDate : .idle
            }
        } catch {
            UsageLog.note("update check failed: \(error)")
            if manual { phase = .checkFailed(Self.describe(error)) }
        }
    }

    func update() async {
        let release: ReleaseInfo
        switch phase {
        case .available(let candidate), .failed(let candidate, _): release = candidate
        default: return
        }
        phase = .downloading(release)
        do {
            let file = try await downloader.download(release)
            UsageLog.note("update downloaded \(release.version)")
            phase = .available(release)
            NSWorkspace.shared.open(file)
        } catch {
            UsageLog.note("update download failed: \(error)")
            phase = .failed(release, Self.describe(error))
        }
    }

    func later() {
        guard case .available(let release) = phase else { return }
        UserDefaults.standard.set(release.version.description, forKey: Self.skippedKey)
        phase = .idle
    }

    func openReleasePage() {
        switch phase {
        case .available(let release), .downloading(let release), .failed(let release, _):
            NSWorkspace.shared.open(release.pageURL)
        default:
            break
        }
    }

    private static func describe(_ error: Error) -> String {
        if let error = error as? UpdateDownloadError {
            switch error {
            case .checksumMismatch: return "the checksum does not match"
            case .checksumMissing: return "the release has no checksum"
            case .download(let message): return message
            }
        }
        if let error = error as? ReleaseCheckError {
            switch error {
            case .http(let code): return "GitHub answered HTTP \(code)"
            case .noUsableRelease: return "no usable release"
            case .unreadable: return "GitHub's answer could not be read"
            }
        }
        return error.localizedDescription
    }
}
```

- [ ] **Step 3: Start it from `AppDelegate`**

In `App/AppDelegate.swift`, right after `self.viewModel = viewModel`, add:

```swift
        UpdateModel.shared.start()
```

- [ ] **Step 4: Build and run the tests**

Run: `swift test` (all pass), then:
`xcodegen generate && xcodebuild -project AgentUsage.xcodeproj -scheme AgentUsageApp -destination 'platform=macOS' -derivedDataPath build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build 2>&1 | grep -E 'error:|BUILD|\.swift.*warning:'`
Expected: `** BUILD SUCCEEDED **`, with no warnings.

- [ ] **Step 5: Commit**

```bash
git add Sources/UsageCore/Network/UsageLog.swift App/UpdateModel.swift App/AppDelegate.swift
git commit -m "feat(update): UpdateModel checks GitHub on a schedule, downloads and opens a verified pkg

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Update UI (menu line, dots, Settings)

**Files:**
- Create: `App/UpdateBanner.swift`
- Modify: `App/MenuContentView.swift`: show the banner under the title.
- Modify: `App/MenuBarLabelView.swift`: the dot.
- Modify: `App/DesktopPanelView.swift`: the dot.
- Modify: `App/PreferencesView.swift`: the "Updates" section.
- Modify: `App/DesktopPanelController.swift`: make the Settings window 640 pt tall instead of 580 pt.

**Interfaces:**
- Consumes: `UpdateModel.shared`, `phase`, `showsDot`, `installed`, `check(manual:)`, `update()`, `later()`, `openReleasePage()` and `UpdateModel.autoCheckKey` (Task 5).
- Produces: `struct UpdateBanner: View { @ObservedObject var updates: UpdateModel }`

- [ ] **Step 1: Write `App/UpdateBanner.swift`**

```swift
import SwiftUI
import UsageCore

struct UpdateBanner: View {
    @ObservedObject var updates: UpdateModel

    var body: some View {
        switch updates.phase {
        case .available(let release):
            HStack {
                Text("gas \(release.version.description) is available").font(.callout.bold())
                Spacer()
                Button("Later") { updates.later() }
                Button("Update") { Task { await updates.update() } }
            }
        case .downloading(let release):
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Downloading gas \(release.version.description)…").font(.callout)
            }
        case .failed(_, let message):
            VStack(alignment: .leading, spacing: 4) {
                Text("Update failed: \(message)").font(.callout).foregroundStyle(.orange)
                HStack {
                    Button("Open release page") { updates.openReleasePage() }
                    Spacer()
                    Button("Try again") { Task { await updates.update() } }
                }
            }
        case .idle, .checking, .upToDate, .checkFailed:
            EmptyView()
        }
    }
}
```

- [ ] **Step 2: Show the banner in the menu**

In `App/MenuContentView.swift`, add the property `@ObservedObject private var updates = UpdateModel.shared` under `let onSetup: () -> Void`. Then, right after the `Text("g · a · s")` block (its `.frame(maxWidth: .infinity)` line) and before the first `Divider()`, add:

```swift
            if updates.showsDot {
                Divider()
                UpdateBanner(updates: updates)
            }
```

- [ ] **Step 3: Add the dot to the menu bar label**

In `App/MenuBarLabelView.swift`, add `@ObservedObject private var updates = UpdateModel.shared` under the `viewModel` property. Then, between `.padding(.horizontal, 4)` and `.fixedSize()`, add:

```swift
        .overlay(alignment: .topTrailing) {
            if updates.showsDot {
                Circle().fill(Color.accentColor).frame(width: 5, height: 5)
            }
        }
```

- [ ] **Step 4: Add the dot to the floating panel**

In `App/DesktopPanelView.swift`, add `@ObservedObject private var updates = UpdateModel.shared` under `@ObservedObject var pointer: PointerTracker`. Then, right after `.modifier(PanelGlass(cornerRadius: 12))`, add the following. The top-left corner keeps the dot away from the layout pill.

```swift
            .overlay(alignment: .topLeading) {
                if updates.showsDot {
                    Circle().fill(Color.accentColor).frame(width: 6, height: 6).padding(5)
                }
            }
```

- [ ] **Step 5: Add the "Updates" section to Settings**

In `App/PreferencesView.swift`:
- Add the properties `@AppStorage(UpdateModel.autoCheckKey) private var checkForUpdates = true` and `@ObservedObject private var updates = UpdateModel.shared`.
- Insert this section right before `Section("Troubleshooting") {`:

```swift
            Section("Updates") {
                Toggle("Check for updates automatically", isOn: $checkForUpdates)
                HStack {
                    Button("Check for updates") { Task { await updates.check(manual: true) } }
                        .disabled(updates.phase == .checking)
                    Spacer()
                    Text(updateStatus).font(.caption).foregroundStyle(.secondary)
                }
            }
```

Add this computed property next to the other private helpers:

```swift
    private var updateStatus: String {
        let installed = updates.installed?.description ?? "?"
        switch updates.phase {
        case .idle: return "Version \(installed)"
        case .checking: return "Checking…"
        case .upToDate: return "Up to date (\(installed))"
        case .checkFailed(let message): return "Couldn't check: \(message)"
        case .available(let release): return "gas \(release.version.description) is available"
        case .downloading: return "Downloading…"
        case .failed(_, let message): return "Update failed: \(message)"
        }
    }
```

- [ ] **Step 6: Make the Settings window taller**

In `App/DesktopPanelController.swift`, change `window.setContentSize(NSSize(width: 380, height: 580))` to `window.setContentSize(NSSize(width: 380, height: 640))`.

- [ ] **Step 7: Build and look at it**

Run: `swift test`, then the `xcodegen` and `xcodebuild` command from Task 5 Step 4.
Expected: all tests pass, and `** BUILD SUCCEEDED **` with no warnings.

Then sign and run the test copy:
`codesign --force --deep --options runtime --sign - build/Build/Products/Debug/AgentUsageApp.app && pkill -x AgentUsageApp; sleep 2; open build/Build/Products/Debug/AgentUsageApp.app`

In Settings → Updates, click **Check for updates**. The status line must show "Up to date (1.0.23)", because v1.0.23 is the latest release.

- [ ] **Step 8: Commit**

```bash
git add App/UpdateBanner.swift App/MenuContentView.swift App/MenuBarLabelView.swift App/DesktopPanelView.swift App/PreferencesView.swift App/DesktopPanelController.swift
git commit -m "feat(update): update line in the menu, dots on the menu bar label and the panel, Updates section in Settings

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Release scripts

**Files:**
- Modify: `scripts/package.sh`: write `<pkg>.sha256` next to the pkg.
- Create: `scripts/publish.sh`
- Create: `scripts/release-notes.md`
- Modify: `scripts/README.md`: add a "Publish a release" section.

**Interfaces:**
- Produces:
  - `dist/gas-<version>.pkg.sha256`
  - `scripts/publish.sh <version>`, which creates the GitHub release `v<version>` in `${GAS_REPO:-gilador/gas}` with the pkg, the dmg and the sha256 file, using the release notes from `scripts/release-notes.md`

- [ ] **Step 1: Write the checksum in `scripts/package.sh`**

Replace this block near the end of the file:

```bash
if [ -n "$PKG" ]; then
  echo "$PKG"
fi
```

with:

```bash
if [ -n "$PKG" ]; then
  (cd "$(dirname "$PKG")" && shasum -a 256 "$(basename "$PKG")" > "$(basename "$PKG").sha256")
  echo "$PKG"
  echo "$PKG.sha256"
fi
```

- [ ] **Step 2: Write `scripts/release-notes.md`**

```markdown
Not a production build: it is not signed with an Apple Developer ID.

**Install**
1. Download the `.pkg` below and open it.
2. If macOS blocks it, click **Done**, then go to **System Settings → Privacy & Security** and click **Open Anyway**.
3. On an update, macOS asks to let Installer modify apps. Click **Allow**.

gas 1.0.24 and later check for updates by themselves and install them from inside the app.
```

- [ ] **Step 3: Write `scripts/publish.sh`**

```bash
#!/bin/bash
# Publishes dist/gas-<version>.{pkg,dmg,pkg.sha256} as the GitHub release v<version>.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: scripts/publish.sh <version>   (set GH_TOKEN to publish with another gh account)}"
REPO="${GAS_REPO:-gilador/gas}"
FILES=("dist/gas-$VERSION.pkg" "dist/gas-$VERSION.dmg" "dist/gas-$VERSION.pkg.sha256")

for file in "${FILES[@]}"; do
  [ -f "$file" ] || { echo "publish.sh: $file not found. Run scripts/package.sh all first." >&2; exit 1; }
done
(cd dist && shasum -a 256 -c "gas-$VERSION.pkg.sha256") >&2

gh release create "v$VERSION" "${FILES[@]}" --repo "$REPO" --target main \
  --title "gas $VERSION" --notes-file scripts/release-notes.md
```

Then run `chmod +x scripts/publish.sh`.

- [ ] **Step 4: Document it in `scripts/README.md`**

Append:

```markdown
## Publish a release

1. Set `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`, and commit.
2. Run `scripts/package.sh all`. It writes the pkg, the dmg and `gas-<version>.pkg.sha256` to `dist/`.
3. Push `main`, then run `scripts/publish.sh <version>`. It checks the checksum, then creates the GitHub release `v<version>` with the three files.
   To publish with a gh account that is not the active one: `GH_TOKEN="$(gh auth token --user <account>)" scripts/publish.sh <version>`.

gas checks the latest release on GitHub. It installs a release only if the release has both `gas-<version>.pkg` and `gas-<version>.pkg.sha256`.
```

- [ ] **Step 5: Check the scripts**

Run: `bash -n scripts/package.sh && bash -n scripts/publish.sh && echo ok`
Expected: `ok`

Run: `scripts/publish.sh` (with no version)
Expected: the usage message, and exit code 1.

- [ ] **Step 6: Commit**

```bash
git add scripts/package.sh scripts/publish.sh scripts/release-notes.md scripts/README.md
git commit -m "build: package.sh writes the pkg checksum; publish.sh creates the GitHub release

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Release 1.0.24 and test the full update path

**Files:**
- Modify: `project.yml`: `MARKETING_VERSION: "1.0.24"`, `CURRENT_PROJECT_VERSION: "28"` (2 places each).

**Interfaces:**
- Consumes: everything above.

- [ ] **Step 1: Bump the version and make the package**

Edit `project.yml` (both targets): `MARKETING_VERSION: "1.0.24"` and `CURRENT_PROJECT_VERSION: "28"`. Move the old files `dist/gas-1.0.23.*` to the Trash. Then run `scripts/package.sh all`.
Expected: `dist/gas-1.0.24.pkg`, `dist/gas-1.0.24.dmg` and `dist/gas-1.0.24.pkg.sha256`, and the line "signing ad-hoc".

Run: `(cd dist && shasum -a 256 -c gas-1.0.24.pkg.sha256)`
Expected: `gas-1.0.24.pkg: OK`

- [ ] **Step 2: Commit, push and publish**

```bash
git add project.yml
git commit -m "release: gas 1.0.24 (in-app updates)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push
GH_TOKEN="$(gh auth token --user gilador)" scripts/publish.sh 1.0.24
```

Expected: the URL of the release `v1.0.24`, which has 3 assets.

- [ ] **Step 3: Test the update path with an older test copy**

Build a test copy that reports an older version. This changes no file.
`xcodebuild -project AgentUsage.xcodeproj -scheme AgentUsageApp -destination 'platform=macOS' -derivedDataPath build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO MARKETING_VERSION=1.0.22 build`
Then sign it ad-hoc and run it, as in Task 6 Step 7.

Check, in this order:
1. Settings → **Check for updates** shows "gas 1.0.24 is available".
2. The menu shows the line with **Update** and **Later**. The menu bar label and the floating panel show the dot.
3. **Later** hides the line and the dots. A manual **Check for updates** shows the version again.
4. **Update** shows "Downloading gas 1.0.24…". Then the Installer opens `gas-1.0.24.pkg` with no Gatekeeper "Open Anyway" step.
5. After the install, the gas that runs is 1.0.24: `defaults read /Applications/gas.app/Contents/Info.plist CFBundleShortVersionString`.
6. Copy diagnostics shows the `update check` and `update downloaded` lines.

- [ ] **Step 4: Remove the test copy from LaunchServices**

Run: `/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$PWD/build/Build/Products/Debug/AgentUsageApp.app"`
