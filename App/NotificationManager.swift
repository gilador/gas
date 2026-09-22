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

    init() {
        center = CodeSignature.isTeamSigned ? UNUserNotificationCenter.current() : nil
    }

    func requestAuthorization() {
        center?.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func post(_ crossings: [ThresholdCrossing]) {
        guard let center else { return }
        for crossing in crossings {
            post(crossing, to: center)
        }
    }

    private func post(_ crossing: ThresholdCrossing, to center: UNUserNotificationCenter) {
        let content = UNMutableNotificationContent()
        content.title = "\(crossing.provider.displayName) \(crossing.limit.label) at \(crossing.limit.displayPercent)%"
        content.body = "You've crossed the \(Int(crossing.threshold))% threshold for this limit."
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                             content: content, trigger: nil)
        center.add(request)
    }
}
