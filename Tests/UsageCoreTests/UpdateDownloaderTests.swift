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
