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

    let alerts = AlertCenter()

    private let registry: ProviderRegistry
    private let store: SnapshotStore
    let notifications: NotificationManager
    private let thresholds = ThresholdMonitor()
    private var timer: Timer?
    private let pathMonitor = NWPathMonitor()
    private var wasConnected = true
    private var recoveryTask: Task<Void, Never>?
    @Published private var recoveringProviders: Set<ProviderID> = []
    private var inFlight: Task<Void, Never>?

    init() {
        let env = ProcessInfo.processInfo.environment
        let claudeBase = env["ANTHROPIC_BASE_URL"].flatMap { URL(string: $0) }
            ?? URL(string: "https://api.anthropic.com")!
        let openAIBase = env["CHATGPT_BASE_URL"].flatMap { URL(string: $0) }
            ?? URL(string: "https://chatgpt.com")!
        self.registry = ProviderRegistry.makeDefault(
            tokenReader: SecurityCLITokenReader(),
            codexAuthReader: FileCodexAuthReader(),
            grokAuthReader: FileGrokAuthReader(),
            httpClient: URLSessionHTTPClient(),
            claudeBaseURL: claudeBase,
            openAIBaseURL: openAIBase,
            claudeRenewer: ClaudeCodeRenewer(isEnabled: { ProviderSettings.renewsClaudeToken() }))
        self.store = SnapshotStore(containerURL: StorageLocation.containerURL(appGroupID: Self.appGroupID))
        self.notifications = NotificationManager()
        self.board = store.load() ?? UsageBoard()
        notifications.requestAuthorization()
        start()
        startNetworkMonitoring()
    }

    private func startNetworkMonitoring() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            Task { @MainActor in
                guard let self, connected != self.wasConnected else { return }
                self.wasConnected = connected
                self.recoveryTask?.cancel()
                self.recoveringProviders = []
                if connected { self.recoverConnection() }
            }
        }
        pathMonitor.start(queue: DispatchQueue(label: "com.gilad.agentusage.network"))
    }

    private func recoverConnection() {
        recoveryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var pending = registry.providers.filter { ProviderSettings.isEnabled($0.id) }
            while !pending.isEmpty {
                if let inFlight { await inFlight.value }
                guard !Task.isCancelled else { return }
                pending.removeAll { !ProviderSettings.isEnabled($0.id) }
                recoveringProviders = Set(pending.map(\.id))
                let now = Date()
                guard let next = UsageRefresher.nextRefreshDate(board, providers: pending, now: now) else { break }
                let delay = next.timeIntervalSince(now)
                if delay > 0 {
                    do {
                        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    } catch { return }
                    continue
                }
                pending.removeAll { UsageRefresher.nextRequestDate(self.board, provider: $0, now: now) <= now }
                await refresh()
            }
            guard !Task.isCancelled else { return }
            recoveringProviders = []
            recoveryTask = nil
        }
    }

    func start() {
        Task { await refresh() }
        scheduleTimer()
    }

    private func scheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: RefreshIntervals.seconds, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.nextTick = Date().addingTimeInterval(RefreshIntervals.seconds)
                await self?.refresh()
            }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
        nextTick = Date().addingTimeInterval(RefreshIntervals.seconds)
    }

    func nextRefresh(for provider: ProviderID) -> Date {
        guard let registered = registry.providers.first(where: { $0.id == provider }) else { return nextTick }
        let eligible = UsageRefresher.nextRequestDate(board, provider: registered)
        return recoveringProviders.contains(provider) ? eligible : max(nextTick, eligible)
    }

    func manualDebounceEnd(now: Date = Date()) -> Date? {
        let providers = registry.providers.filter { ProviderSettings.isEnabled($0.id) }
        guard let next = UsageRefresher.nextRefreshDate(board, providers: providers, now: now, manual: true),
              next > now else { return nil }
        return next
    }

    func diagnosticsReport(now: Date = Date()) -> String {
        let info = Bundle.main.infoDictionary
        let version = "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
        let token = Result(catching: { try SecurityCLITokenReader().readClaudeToken() })
        return DiagnosticsReport.render(appVersion: version,
                                        osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                                        now: now,
                                        keychainEntries: ClaudeKeychainEntries.list(),
                                        tokenStatus: DiagnosticsReport.tokenStatus(token, now: now),
                                        board: board,
                                        recentLog: UsageLog.recentLines())
    }

    /// Snapshots for enabled providers only; disabled providers stay hidden everywhere.
    var visibleSnapshots: [UsageSnapshot] {
        board.snapshots.filter { ProviderSettings.isEnabled($0.provider) }
    }

    func refresh(manual: Bool = false) async {
        if let inFlight { return await inFlight.value }
        let task = Task { @MainActor in
            let updated = await UsageRefresher.refresh(board, providers: registry.providers.filter { ProviderSettings.isEnabled($0.id) }, manual: manual)
            board = updated
            try? store.save(updated)
            let crossings = thresholds.crossings(in: updated)
            notifications.post(crossings)
            alerts.raise(crossings, criticalIf: thresholds.isCritical)
            WidgetCenter.shared.reloadAllTimelines()
            if manual { scheduleTimer() }
            inFlight = nil
        }
        inFlight = task
        await task.value
    }
}
