import Foundation
import UserNotifications

@MainActor
final class APNotificationService {
    static let shared = APNotificationService()

    private(set) var isAppActive = true
    private var permissionRequested = false

    private init() {}

    func setAppActive(_ active: Bool) {
        isAppActive = active
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
            permissionRequested = true
            return await withCheckedContinuation { continuation in
                center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }

    func notifyChat(args: [String: Any], context: APContext) {
        guard Persistence.notificationsEnabled,
              Persistence.notificationChatEnabled,
              APNotificationFilter.shouldNotifyChat(args, context: context) else {
            return
        }
        guard shouldDeliverNow() else { return }

        let title = APNotificationFilter.chatNotificationTitle(args, context: context)
        let body = APNotificationFilter.chatNotificationBody(args, context: context)
        schedule(title: title, body: body)
    }

    func notifyReceivedItem(_ item: NetworkItem, context: APContext) {
        guard Persistence.notificationsEnabled,
              Persistence.notificationItemsEnabled else {
            return
        }
        guard shouldDeliverNow() else { return }

        let title = APNotificationFilter.itemNotificationTitle(item)
        let body = APNotificationFilter.itemNotificationBody(item, context: context)
        schedule(title: title, body: body)
    }

    private func shouldDeliverNow() -> Bool {
        if isAppActive && !Persistence.notificationForegroundEnabled {
            return false
        }
        return true
    }

    private func schedule(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request)
    }
}
