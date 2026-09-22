import Foundation
import UsageCore

@MainActor
final class ThresholdMonitor {
    private let defaults = UserDefaults.standard
    private let stateKey = "alertState"
    private let legacyStateKey = "notificationState"

    var criticalThreshold: Double {
        defaults.object(forKey: "criticalThreshold") as? Double ?? 85
    }

    func isCritical(_ crossing: ThresholdCrossing) -> Bool {
        crossing.level == .critical
    }

    func crossings(in board: UsageBoard) -> [ThresholdCrossing] {
        let warning = defaults.object(forKey: "warningThreshold") as? Double ?? 65
        let upgrading = defaults.data(forKey: stateKey) == nil && defaults.object(forKey: legacyStateKey) != nil
        var state = loadState()
        var crossings: [ThresholdCrossing] = []
        for snapshot in board.snapshots where snapshot.status == .ok {
            crossings += ThresholdEvaluator.evaluate(snapshot, state: &state,
                                                     warning: warning, critical: criticalThreshold)
        }
        saveState(state)
        if upgrading {
            // Old per-threshold flags mean these windows were already alerted; start the new flags silently.
            defaults.removeObject(forKey: legacyStateKey)
            return []
        }
        return crossings
    }

    private func loadState() -> NotificationState {
        guard let data = defaults.data(forKey: stateKey),
              let state = try? JSONDecoder().decode(NotificationState.self, from: data) else {
            return NotificationState()
        }
        return state
    }

    private func saveState(_ state: NotificationState) {
        if let data = try? JSONEncoder().encode(state) {
            defaults.set(data, forKey: stateKey)
        }
    }
}
