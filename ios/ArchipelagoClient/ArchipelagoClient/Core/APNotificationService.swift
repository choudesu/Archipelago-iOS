import Foundation
import UserNotifications

@MainActor
final class APNotificationService {
    static let shared = APNotificationService()

    private static let disconnectNotificationID = "archipelago.disconnect"

    private(set) var isAppActive = true
    private(set) var leftAppWhileJoined = false

    private init() {}

    func setAppActive(_ active: Bool, joined: Bool) {
        if !active && joined {
            leftAppWhileJoined = true
        }
        isAppActive = active
        if active {
            cancelPendingDisconnectNotification()
        }
    }

    func clearBackgroundDisconnectState() {
        leftAppWhileJoined = false
    }

    func requestPermissionIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }

    func notifyDisconnectedDueToBackground(wasJoined: Bool, intentional: Bool) {
        guard Persistence.notificationsEnabled,
              wasJoined,
              !intentional,
              !isAppActive || leftAppWhileJoined else {
            return
        }

        scheduleDisconnectNotification()
        leftAppWhileJoined = false
    }

    private func scheduleDisconnectNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Disconnected from Archipelago"
        content.body = "The app was closed or backgrounded. Reopen to reconnect to the multiworld."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(
            identifier: Self.disconnectNotificationID,
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func cancelPendingDisconnectNotification() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [Self.disconnectNotificationID])
    }
}
