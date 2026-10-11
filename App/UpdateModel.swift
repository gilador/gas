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
