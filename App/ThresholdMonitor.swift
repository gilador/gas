import Foundation
import UsageCore

@MainActor
final class ThresholdMonitor {
    private let defaults = UserDefaults.standard
    private let stateKey = "notificationState"

    func crossings(in board: UsageBoard) -> [ThresholdCrossing] {
        let thresholds = [
            defaults.object(forKey: "warningThreshold") as? Double ?? 80,
            defaults.object(forKey: "criticalThreshold") as? Double ?? 95
        ]
        var state = loadState()
        var crossings: [ThresholdCrossing] = []
        for snapshot in board.snapshots where snapshot.status == .ok {
            crossings += ThresholdEvaluator.evaluate(snapshot, state: &state, thresholds: thresholds)
        }
        saveState(state)
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
