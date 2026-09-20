import Foundation
import UserNotifications
import UsageCore

final class NotificationManager {
    /// The notification center is optional and only obtained when the app is
    /// signed with a real team identity. In an unsigned / ad-hoc-signed build,
    /// `UNUserNotificationCenter.current()` throws an NSException on an internal
    /// dispatch queue during lazy init, which is uncatchable and aborts the
    /// process (SIGABRT) at launch. Requiring a real team signature avoids
    /// touching UNUserNotificationCenter in those builds.
    private let center: UNUserNotificationCenter?
    private let defaults = UserDefaults.standard
    private let stateKey = "notificationState"

    init() {
        center = CodeSignature.isTeamSigned ? UNUserNotificationCenter.current() : nil
    }

    func requestAuthorization() {
        center?.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func process(_ board: UsageBoard) {
        guard let center else { return }
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
        for crossing in crossings {
            post(crossing, to: center)
        }
    }

    private func post(_ crossing: ThresholdCrossing, to center: UNUserNotificationCenter) {
        let content = UNMutableNotificationContent()
        content.title = "\(crossing.provider.displayName) \(crossing.limit.label) at \(Int(crossing.limit.percentUsed.rounded()))%"
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
