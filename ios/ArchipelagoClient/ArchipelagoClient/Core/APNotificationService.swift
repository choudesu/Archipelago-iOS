import Foundation
import UIKit
import UserNotifications

@MainActor
final class APNotificationService {
    static let shared = APNotificationService()

    private static let disconnectNotificationID = "archipelago.disconnect"
    private static let minimumTriggerInterval: TimeInterval = 1

    private(set) var isAppActive = true
    private(set) var leftAppWhileJoined = false

    private init() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isAppActive = false
            }
        }
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isAppActive = true
            }
        }
    }

    func handleEnterBackground(joined: Bool, connected: Bool) {
        isAppActive = false
        guard joined, connected, Persistence.notificationsEnabled else { return }

        leftAppWhileJoined = true
    }

    func handleEnterForeground() {
        isAppActive = true
        cancelPendingDisconnectNotification()
        clearBackgroundDisconnectState()
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
              leftAppWhileJoined || !isAppActive else {
            return
        }

        Task {
            guard await requestPermissionIfNeeded() else { return }
            scheduleDisconnectNotification()
            clearBackgroundDisconnectState()
        }
    }

    private func scheduleDisconnectNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Disconnected from Applepelago"
        content.body = "Lost connection to the multiworld server. Reopen Applepelago to reconnect."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: Self.minimumTriggerInterval,
            repeats: false
        )
        let request = UNNotificationRequest(
            identifier: Self.disconnectNotificationID,
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                NSLog("Failed to schedule disconnect notification: \(error.localizedDescription)")
            }
        }
    }

    private func cancelPendingDisconnectNotification() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [Self.disconnectNotificationID])
    }

    func scheduleActivityNotification(_ event: ActivityEvent) async {
        guard Persistence.activityAlertsEnabled else { return }
        guard await requestPermissionIfNeeded() else { return }

        let content = UNMutableNotificationContent()
        content.title = event.title
        content.body = event.message
        content.sound = .default
        content.categoryIdentifier = event.kind == .item ? "ACTIVITY_ITEM" : "ACTIVITY_HINT"

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: Self.minimumTriggerInterval,
            repeats: false
        )
        let identifier = "activity.\(event.dedupKey)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                NSLog("Failed to schedule activity notification: \(error.localizedDescription)")
            }
        }
    }
}
