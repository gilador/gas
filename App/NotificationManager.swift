import Foundation
import UserNotifications
import UsageCore

final class NotificationManager {
    private let center = UNUserNotificationCenter.current()
    private let defaults = UserDefaults.standard
    private let stateKey = "notificationState"

    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func process(_ snapshot: UsageSnapshot) {
        guard snapshot.status == .ok else { return }
        let thresholds = [
            defaults.object(forKey: "warningThreshold") as? Double ?? 80,
            defaults.object(forKey: "criticalThreshold") as? Double ?? 95
        ]
        var state = loadState()
        let crossings = ThresholdEvaluator.evaluate(snapshot, state: &state, thresholds: thresholds)
        saveState(state)
        for crossing in crossings {
            post(crossing)
        }
    }

    private func post(_ crossing: ThresholdCrossing) {
        let content = UNMutableNotificationContent()
        content.title = "\(crossing.limit.label) at \(Int(crossing.limit.percentUsed.rounded()))%"
        content.body = "You've crossed the \(Int(crossing.threshold))% threshold for this limit."
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                             content: content, trigger: nil)
        center.add(request)
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
