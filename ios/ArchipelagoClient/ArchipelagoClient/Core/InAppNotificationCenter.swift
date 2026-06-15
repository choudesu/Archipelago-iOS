import Foundation
import SwiftUI

struct InAppNotification: Identifiable, Equatable {
    let id: UUID
    let kind: ActivityNotificationKind
    let title: String
    let message: String
    let dedupKey: String

    init(event: ActivityEvent, id: UUID = UUID()) {
        self.id = id
        self.kind = event.kind
        self.title = event.title
        self.message = event.message
        self.dedupKey = event.dedupKey
    }
}

@MainActor
final class InAppNotificationCenter: ObservableObject {
    static let maxVisible = 3
    static let autoDismissSeconds: TimeInterval = 5

    @Published private(set) var active: [InAppNotification] = []

    private var dismissTasks: [UUID: Task<Void, Never>] = [:]

    func post(_ event: ActivityEvent) {
        if active.contains(where: { $0.dedupKey == event.dedupKey }) {
            return
        }

        let notification = InAppNotification(event: event)
        active.insert(notification, at: 0)
        if active.count > Self.maxVisible {
            let removed = active.suffix(from: Self.maxVisible)
            for item in removed {
                dismissTasks[item.id]?.cancel()
                dismissTasks[item.id] = nil
            }
            active = Array(active.prefix(Self.maxVisible))
        }

        dismissTasks[notification.id]?.cancel()
        dismissTasks[notification.id] = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(Self.autoDismissSeconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            dismiss(notification.id)
        }
    }

    func dismiss(_ id: UUID) {
        dismissTasks[id]?.cancel()
        dismissTasks[id] = nil
        active.removeAll { $0.id == id }
    }
}
