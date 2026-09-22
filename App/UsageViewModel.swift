import Foundation
import Combine
import Network
import WidgetKit
import UsageCore

@MainActor
final class UsageViewModel: ObservableObject {
    static let appGroupID = "group.com.gilad.agentusage"

    @Published var board: UsageBoard
    @Published private(set) var nextTick: Date = Date()

    private let registry: ProviderRegistry
    private let store: SnapshotStore
    private let notifications: NotificationManager
    private var timer: Timer?
    private let pathMonitor = NWPathMonitor()
    private var wasConnected = true
    private var inFlight: Task<Void, Never>?

    init() {
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
        self.store = SnapshotStore(containerURL: StorageLocation.containerURL(appGroupID: Self.appGroupID))
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
                    await self.refresh(manual: false)
                }
                self.wasConnected = connected
            }
        }
        pathMonitor.start(queue: DispatchQueue(label: "com.gilad.agentusage.network"))
    }

    func start() {
        timer?.invalidate()
        Task { await refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: RefreshIntervals.seconds, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.nextTick = Date().addingTimeInterval(RefreshIntervals.seconds)
                await self?.refresh()
            }
        }
        nextTick = Date().addingTimeInterval(RefreshIntervals.seconds)
    }

    /// When the next request to this provider can happen: the next tick, unless a rate-limit deadline or the provider's minimum interval is later.
    func nextRefresh(for provider: ProviderID) -> Date {
        var next = nextTick
        if let last = board.lastRequest(for: provider),
           let minimum = registry.providers.first(where: { $0.id == provider })?.minimumInterval {
            next = max(next, last.addingTimeInterval(minimum))
        }
        if case .rateLimited(let until, _)? = board.snapshot(for: provider)?.status {
            next = max(next, until)
        }
        return next
    }

    func refresh(manual: Bool = false) async {
        if let inFlight { return await inFlight.value }
        let task = Task { @MainActor in
            let updated = await UsageRefresher.refresh(board, providers: registry.providers,
                                                        ignoreMinimumInterval: manual)
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
