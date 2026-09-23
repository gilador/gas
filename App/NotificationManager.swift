import AppKit
import Foundation
import UserNotifications
import os
import UsageCore

@MainActor
final class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    enum Permission { case unavailable, notDetermined, denied, allowed, blockedBySigning }

    @Published private(set) var permission: Permission = .unavailable
    private var blockedBySigning = false

    /// Only obtained for team-signed builds: in an ad-hoc build `UNUserNotificationCenter.current()`
    /// raises an uncatchable exception at launch.
    private let center: UNUserNotificationCenter?
    private let log = Logger(subsystem: "com.gilad.agentusage", category: "notifications")

    override init() {
        center = CodeSignature.isTeamSigned ? UNUserNotificationCenter.current() : nil
        super.init()
        center?.delegate = self
    }

    func requestAuthorization() {
        guard let center else {
            log.notice("notifications unavailable: build is not team-signed")
            return
        }
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, error in
            Task { @MainActor in
                if let error {
                    self?.log.error("authorization failed: \(error.localizedDescription, privacy: .public)")
                    // UNError.notificationsNotAllowed: macOS only registers Gatekeeper-accepted (Developer ID) apps.
                    if (error as NSError).domain == UNErrorDomain, (error as NSError).code == UNError.Code.notificationsNotAllowed.rawValue {
                        self?.blockedBySigning = true
                    }
                } else {
                    self?.log.notice("authorization granted: \(granted, privacy: .public)")
                }
                await self?.refreshPermission()
            }
        }
    }

    func refreshPermission() async {
        guard let center else { permission = .unavailable; return }
        if blockedBySigning { permission = .blockedBySigning; return }
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional: permission = .allowed
        case .notDetermined: permission = .notDetermined
        default: permission = .denied
        }
    }

    func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=com.gilad.agentusage")!
        NSWorkspace.shared.open(url)
    }

    /// One notification per limit, at its strongest level in this batch.
    func post(_ crossings: [ThresholdCrossing]) {
        guard let center else { return }
        var strongest: [String: ThresholdCrossing] = [:]
        for crossing in crossings {
            let key = "\(crossing.provider.rawValue)#\(crossing.limit.id)"
            if strongest[key]?.level == .critical { continue }
            strongest[key] = crossing
        }
        for (key, crossing) in strongest.sorted(by: { $0.key < $1.key }) {
            let content = UNMutableNotificationContent()
            content.title = "\(crossing.provider.displayName) · \(crossing.limit.label) at \(crossing.limit.displayPercent)%"
            content.body = crossing.level == .critical
                ? "Critical gas limit reached (\(Int(crossing.threshold))%)."
                : "Running low: past the \(Int(crossing.threshold))% warning."
            content.sound = .default
            content.threadIdentifier = crossing.provider.rawValue
            let request = UNNotificationRequest(identifier: "\(key)#\(crossing.level.rawValue)", content: content, trigger: nil)
            center.add(request) { [weak self] error in
                if let error {
                    self?.log.error("post failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
