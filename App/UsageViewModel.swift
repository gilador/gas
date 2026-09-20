import Foundation
import Combine
import Network
import WidgetKit
import UsageCore

@MainActor
final class UsageViewModel: ObservableObject {
    static let appGroupID = "group.com.gilad.agentusage"

    @Published var board: UsageBoard
    var refreshInterval: TimeInterval

    private let registry: ProviderRegistry
    private let store: SnapshotStore
    private let notifications: NotificationManager
    private var timer: Timer?
    private let pathMonitor = NWPathMonitor()
    private var wasConnected = true
    private var inFlight: Task<Void, Never>?

    init(refreshInterval: TimeInterval? = nil) {
        let stored = UserDefaults.standard.object(forKey: "refreshInterval") as? Double
        self.refreshInterval = refreshInterval ?? RefreshIntervals.snapped(stored ?? RefreshIntervals.defaultSeconds)
        let env = ProcessInfo.processInfo.environment
        let claudeBase = env["ANTHROPIC_BASE_URL"].flatMap { URL(string: $0) }
            ?? URL(string: "https://api.anthropic.com")!
        let openAIBase = env["CHATGPT_BASE_URL"].flatMap { URL(string: $0) }
            ?? URL(string: "https://chatgpt.com")!
        self.registry = ProviderRegistry.makeDefault(
            tokenReader: KeychainTokenReader(),
            codexAuthReader: FileCodexAuthReader(),
            httpClient: URLSessionHTTPClient(),
            claudeBaseURL: claudeBase,
            openAIBaseURL: openAIBase)
        self.store = SnapshotStore(appGroupID: Self.appGroupID)
        self.notifications = NotificationManager()
        self.board = store.load() ?? UsageBoard()
        notifications.requestAuthorization()
        start()
        startNetworkMonitoring()
    }

    /// Refresh immediately when the network comes back (like Gmail reconnecting),
    /// instead of waiting for the next scheduled tick.
    private func startNetworkMonitoring() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            Task { @MainActor in
                guard let self else { return }
                if connected && !self.wasConnected {
                    await self.refresh()
                }
                self.wasConnected = connected
            }
        }
        pathMonitor.start(queue: DispatchQueue(label: "com.gilad.agentusage.network"))
    }

    func start() {
        timer?.invalidate()
        Task { await refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    func refresh() async {
        if let inFlight { return await inFlight.value }
        let task = Task { @MainActor in
            let updated = await UsageRefresher.refresh(board, providers: registry.providers)
            board = updated
            try? store.save(updated)
            notifications.process(updated)
            WidgetCenter.shared.reloadAllTimelines()
        }
        inFlight = task
        await task.value
        inFlight = nil
    }
}
