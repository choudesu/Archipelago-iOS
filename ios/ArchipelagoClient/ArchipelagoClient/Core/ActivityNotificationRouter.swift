import Foundation

@MainActor
final class ActivityNotificationRouter {
    let inAppCenter: InAppNotificationCenter

    private var recentlyDeliveredKeys: [String: Date] = [:]
    private static let dedupWindow: TimeInterval = 120

    init(inAppCenter: InAppNotificationCenter) {
        self.inAppCenter = inAppCenter
    }

    func deliver(_ event: ActivityEvent) {
        guard Persistence.activityAlertsEnabled else { return }
        guard !wasRecentlyDelivered(event.dedupKey) else { return }

        if APNotificationService.shared.effectiveIsAppActive {
            inAppCenter.post(event)
        } else {
            Task {
                await APNotificationService.shared.scheduleActivityNotification(event)
            }
        }

        markDelivered(event.dedupKey)
    }

    func deliverFromBackground(_ event: ActivityEvent) {
        guard Persistence.activityAlertsEnabled else { return }
        guard !wasRecentlyDelivered(event.dedupKey) else { return }

        Task {
            await APNotificationService.shared.scheduleActivityNotification(event)
            markDelivered(event.dedupKey)
        }
    }

    func clearRecentDeliveries() {
        recentlyDeliveredKeys = [:]
    }

    private func wasRecentlyDelivered(_ key: String) -> Bool {
        pruneDeliveredKeys()
        guard let deliveredAt = recentlyDeliveredKeys[key] else { return false }
        return Date().timeIntervalSince(deliveredAt) < Self.dedupWindow
    }

    private func markDelivered(_ key: String) {
        recentlyDeliveredKeys[key] = Date()
        pruneDeliveredKeys()
    }

    private func pruneDeliveredKeys() {
        let cutoff = Date().addingTimeInterval(-Self.dedupWindow)
        recentlyDeliveredKeys = recentlyDeliveredKeys.filter { $0.value >= cutoff }
    }
}
