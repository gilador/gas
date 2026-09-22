import Foundation
import UsageCore

@MainActor
final class AlertCenter: ObservableObject {
    @Published private(set) var alertStart: [ProviderID: Date] = [:]
    var onFirstAlert: (() -> Void)?
    var onAllAlertsEnded: (() -> Void)?
    private var expiry: Task<Void, Never>?

    func raise(_ providers: Set<ProviderID>, at now: Date = Date()) {
        guard !providers.isEmpty else { return }
        let wasEmpty = alertStart.isEmpty
        for p in providers { alertStart[p] = now }
        if wasEmpty { onFirstAlert?() }
        expiry?.cancel()
        expiry = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(AlertBlink.duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.alertStart.removeAll()
            self?.onAllAlertsEnded?()
        }
    }
}
