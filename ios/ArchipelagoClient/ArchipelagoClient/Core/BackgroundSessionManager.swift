import Foundation
import UIKit

@MainActor
final class BackgroundSessionManager {
    static let shared = BackgroundSessionManager()

    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private var graceTask: Task<Void, Never>?

    private init() {}

    func beginBackgroundGracePeriod(onExpire: @escaping () -> Void) {
        endBackgroundGracePeriod()

        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "ApplepelagoSession") {
            onExpire()
            self.endBackgroundGracePeriod()
        }

        graceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 25_000_000_000)
            guard !Task.isCancelled else { return }
            onExpire()
            endBackgroundGracePeriod()
        }
    }

    func endBackgroundGracePeriod() {
        graceTask?.cancel()
        graceTask = nil
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }
}
