import Foundation
import Combine
import WidgetKit
import UsageCore

@MainActor
final class UsageViewModel: ObservableObject {
    static let appGroupID = "group.com.gilad.agentusage"

    @Published var snapshot: UsageSnapshot?
    var refreshInterval: TimeInterval

    private let registry: ProviderRegistry
    private let store: SnapshotStore
    private let notifications: NotificationManager
    private var timer: Timer?

    init(refreshInterval: TimeInterval? = nil) {
        let stored = UserDefaults.standard.object(forKey: "refreshInterval") as? Double
        self.refreshInterval = refreshInterval ?? stored ?? 780   // default 13 min
        let base = ProcessInfo.processInfo.environment["ANTHROPIC_BASE_URL"]
            .flatMap { URL(string: $0) } ?? URL(string: "https://api.anthropic.com")!
        self.registry = ProviderRegistry.makeDefault(
            tokenReader: KeychainTokenReader(),
            httpClient: URLSessionHTTPClient(),
            baseURL: base)
        self.store = SnapshotStore(appGroupID: Self.appGroupID)
        self.notifications = NotificationManager()
        self.snapshot = store.load()
        notifications.requestAuthorization()
        start()
    }

    func start() {
        timer?.invalidate()
        Task { await refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    func refresh() async {
        guard let provider = registry.providers.first else { return }
        let fetched = (try? await provider.fetch())
            ?? UsageSnapshot(provider: .claude, fetchedAt: Date(), limits: [], status: .error(message: "Fetch failed"))

        let snap: UsageSnapshot
        switch fetched.status {
        case .stale, .error:
            if fetched.limits.isEmpty, let previous = self.snapshot, !previous.limits.isEmpty {
                // Preserve last-good limits + their timestamp; surface the transient status.
                snap = UsageSnapshot(provider: fetched.provider,
                                     fetchedAt: previous.fetchedAt,
                                     limits: previous.limits,
                                     status: fetched.status)
            } else {
                snap = fetched
            }
        case .ok, .needsSignIn, .keychainDenied:
            snap = fetched
        }

        self.snapshot = snap
        try? store.save(snap)
        notifications.process(snap)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
