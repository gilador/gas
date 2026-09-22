import Foundation
import UsageCore

@MainActor
final class AlertCenter: ObservableObject {
    struct ActiveAlert {
        let start: Date
        let critical: Bool
    }

    @Published private(set) var active: [ProviderID: ActiveAlert] = [:]
    var onFirstAlert: (() -> Void)?
    var onAllAlertsEnded: (() -> Void)?
    var onCritical: (([ThresholdCrossing]) -> Void)?
    private var expiry: Task<Void, Never>?

    func raise(_ crossings: [ThresholdCrossing], criticalIf: (ThresholdCrossing) -> Bool, at now: Date = Date()) {
        guard !crossings.isEmpty else { return }
        let wasEmpty = active.isEmpty
        for crossing in crossings {
            let existing = active[crossing.provider]
            active[crossing.provider] = ActiveAlert(start: now, critical: existing?.critical == true || criticalIf(crossing))
        }
        if wasEmpty { onFirstAlert?() }
        var seen = Set<String>()
        let critical = crossings.filter { criticalIf($0) && seen.insert("\($0.provider.rawValue)#\($0.limit.id)").inserted }
        if !critical.isEmpty { onCritical?(critical) }
        expiry?.cancel()
        expiry = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(AlertBlink.duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.active.removeAll()
            self?.onAllAlertsEnded?()
        }
    }
}
