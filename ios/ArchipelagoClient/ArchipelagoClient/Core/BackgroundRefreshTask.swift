import BackgroundTasks
import Foundation

enum BackgroundRefreshTask {
    static let identifier = "jp.chaoticly.ArchipelagoClient.refresh"
    private static let minimumInterval: TimeInterval = 15 * 60

    static func register() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: identifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in
                await handle(refreshTask)
            }
        }
    }

    static func schedule(earliestInterval: TimeInterval? = nil) {
        guard Persistence.backgroundSyncEnabled,
              Persistence.hasBackgroundSessionCredentials else {
            return
        }

        let interval = earliestInterval ?? minimumInterval
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: interval)

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            NSLog("Could not schedule background refresh: \(error.localizedDescription)")
        }
    }

    @MainActor
    static func handle(_ task: BGAppRefreshTask) async {
        schedule()

        let expiration = BackgroundSyncRunner()
        task.expirationHandler = {
            Task { @MainActor in
                await expiration.cancel()
            }
        }

        let success = await expiration.run()
        task.setTaskCompleted(success: success)
    }
}

@MainActor
private final class BackgroundSyncRunner {
    private var context: APContext?
    private var router: ActivityNotificationRouter?
    private var cancelled = false

    func cancel() async {
        cancelled = true
        context?.disconnect()
        context = nil
    }

    func run() async -> Bool {
        guard Persistence.backgroundSyncEnabled,
              Persistence.hasBackgroundSessionCredentials else {
            return false
        }

        let snapshot = Persistence.loadActivitySnapshot()
        let inAppCenter = InAppNotificationCenter()
        let router = ActivityNotificationRouter(inAppCenter: inAppCenter)
        self.router = router

        let context = APContext(
            serverAddress: Persistence.lastServerAddress,
            password: Persistence.backgroundSessionPassword
        )
        context.activityRouter = router
        context.setSlotName(Persistence.lastSlotName)
        self.context = context

        let connected = await waitForConnection(context: context, timeout: 20)
        guard connected, !cancelled else {
            context.disconnect()
            return false
        }

        try? await Task.sleep(nanoseconds: 2_000_000_000)
        guard !cancelled else {
            context.disconnect()
            return false
        }

        deliverNewItemsSinceSnapshot(context: context, snapshot: snapshot, router: router)
        deliverNewHintsSinceSnapshot(context: context, snapshot: snapshot, router: router)

        context.persistActivitySnapshot()
        context.disconnect()
        self.context = nil
        return true
    }

    private func waitForConnection(context: APContext, timeout: TimeInterval) async -> Bool {
        await withCheckedContinuation { continuation in
            let waiter = BackgroundConnectWaiter { success in
                continuation.resume(returning: success)
            }
            context.delegate = waiter
            context.connect()
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                waiter.timeout()
            }
        }
    }

    private func deliverNewItemsSinceSnapshot(
        context: APContext,
        snapshot: ActivitySnapshot,
        router: ActivityNotificationRouter
    ) {
        guard context.itemsReceived.count > snapshot.itemCount else { return }
        let newItems = Array(context.itemsReceived.suffix(context.itemsReceived.count - snapshot.itemCount))
        for item in newItems {
            let event = ActivityNotificationBuilder.itemEvent(
                item: item,
                nameLookup: context.nameLookup,
                playerNames: context.playerNames,
                slotInfo: context.slotInfo
            )
            router.deliverFromBackground(event)
        }
    }

    private func deliverNewHintsSinceSnapshot(
        context: APContext,
        snapshot: ActivitySnapshot,
        router: ActivityNotificationRouter
    ) {
        let knownKeys = Set(snapshot.seenHintKeys)
        for hint in context.hints {
            let key = ActivityNotificationBuilder.hintKey(for: hint)
            guard !knownKeys.contains(key) else { continue }
            guard ActivityNotificationBuilder.hintInvolvesSelf(
                receivingPlayer: hint.receivingPlayer,
                findingPlayer: hint.findingPlayer,
                slotConcernsSelf: context.slotConcernsSelf
            ) else { continue }
            router.deliverFromBackground(ActivityNotificationBuilder.hintEvent(
                hint: hint,
                nameLookup: context.nameLookup,
                playerNames: context.playerNames,
                slotInfo: context.slotInfo
            ))
        }
    }
}

@MainActor
private final class BackgroundConnectWaiter: APContextDelegate {
    private let onComplete: (Bool) -> Void
    private var finished = false

    init(onComplete: @escaping (Bool) -> Void) {
        self.onComplete = onComplete
    }

    func timeout() {
        finish(false)
    }

    private func finish(_ success: Bool) {
        guard !finished else { return }
        finished = true
        onComplete(success)
    }

    func contextDidUpdateConnectionState(_ context: APContext) {}

    func contextDidReceiveLog(_ context: APContext, entry: ChatLogEntry) {}

    func contextDidReceiveError(_ context: APContext, title: String, message: String) {
        finish(false)
    }

    func contextNeedsUserInput(_ context: APContext, prompt: String) async -> String {
        finish(false)
        return ""
    }

    func contextDidUpdateHints(_ context: APContext) {}

    func contextDidUpdateProgress(_ context: APContext) {}

    func contextDidConnect(_ context: APContext) {
        finish(true)
    }

    func contextDidReceiveSlotData(_ context: APContext, slotData: [String: Any]) {}

    func contextDidUpdateCheckedLocations(_ context: APContext, locationIDs: Set<Int>) {}
}
