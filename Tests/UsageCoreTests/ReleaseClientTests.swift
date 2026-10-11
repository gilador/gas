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
