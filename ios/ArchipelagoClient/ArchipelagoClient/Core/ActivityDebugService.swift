import Foundation

@MainActor
enum ActivityDebugService {
    struct Status: Equatable {
        var isAppActive: Bool
        var activityAlertsEnabled: Bool
        var backgroundSyncEnabled: Bool
        var hasSessionCredentials: Bool
        var snapshotItemCount: Int
        var snapshotHintKeyCount: Int
        var liveItemCount: Int
        var liveHintCount: Int
        var isConnected: Bool
        var slot: Int?
    }

    static func status(for context: APContext) -> Status {
        let snapshot = Persistence.loadActivitySnapshot()
        return Status(
            isAppActive: APNotificationService.shared.isAppActive,
            activityAlertsEnabled: Persistence.activityAlertsEnabled,
            backgroundSyncEnabled: Persistence.backgroundSyncEnabled,
            hasSessionCredentials: Persistence.hasBackgroundSessionCredentials,
            snapshotItemCount: snapshot.itemCount,
            snapshotHintKeyCount: snapshot.seenHintKeys.count,
            liveItemCount: context.itemsReceived.count,
            liveHintCount: context.hints.count,
            isConnected: context.isConnected,
            slot: context.slot
        )
    }

    @discardableResult
    static func simulateItemAlert(
        context: APContext,
        router: ActivityNotificationRouter,
        itemID: Int = 1,
        locationID: Int = 2,
        player: Int? = nil
    ) -> ActivityEvent {
        let sender = player ?? context.slot ?? 1
        let item = NetworkItem(item: itemID, location: locationID, player: sender, flags: 0)
        let event = ActivityNotificationBuilder.itemEvent(
            item: item,
            nameLookup: context.nameLookup,
            playerNames: context.playerNames,
            slotInfo: context.slotInfo
        )
        router.deliver(event)
        return event
    }

    @discardableResult
    static func simulateHintAlert(
        context: APContext,
        router: ActivityNotificationRouter,
        receivingPlayer: Int? = nil,
        findingPlayer: Int? = nil
    ) -> ActivityEvent {
        let slot = context.slot ?? 1
        let receiving = receivingPlayer ?? slot
        let finding = findingPlayer ?? slot
        let event = ActivityNotificationBuilder.hintEvent(
            receivingPlayer: receiving,
            findingPlayer: finding,
            itemID: 100,
            locationID: 200,
            itemFlags: 0,
            entrance: "Debug Entrance",
            nameLookup: context.nameLookup,
            playerNames: context.playerNames,
            slotInfo: context.slotInfo
        )
        router.deliver(event)
        return event
    }

    static func simulateReceivedItemsPath(
        context: APContext,
        itemID: Int = 10,
        locationID: Int = 20
    ) {
        if context.slot == nil {
            context.slot = 1
            context.setSlotName("DebugSlot")
        }
        let item = NetworkItem(item: itemID, location: locationID, player: context.slot ?? 1, flags: 0)
        context.itemsReceived.append(item)
        context.notifyNewItems([item], isBulkResync: false)
    }

    static func simulatePrintJSONHintPath(context: APContext) {
        if context.slot == nil {
            context.slot = 1
            context.setSlotName("DebugSlot")
        }
        let slot = context.slot ?? 1
        let locationID = Int.random(in: 10_000...99_999)
        context.onPrintJSON([
            "type": "Hint",
            "receiving": slot,
            "item": [
                "item": locationID + 1,
                "location": locationID,
                "player": slot,
                "flags": 0
            ],
            "data": []
        ])
    }

    static func simulateRefreshHintsPath(context: APContext) {
        if context.team == nil { context.team = 0 }
        if context.slot == nil {
            context.slot = 1
            context.setSlotName("DebugSlot")
        }
        guard let team = context.team, let slot = context.slot else { return }
        let key = "_read_hints_\(team)_\(slot)"

        if context.storedData[key] == nil {
            context.storedData[key] = [[String: Any]]()
            context.refreshHints()
        }

        let locationID = Int.random(in: 10_000...99_999)
        let hintPayload: [String: Any] = [
            "receiving_player": slot,
            "finding_player": slot,
            "location": locationID,
            "item": locationID + 1,
            "found": false,
            "entrance": "Debug Cave",
            "item_flags": 0,
            "status": HintStatus.priority.rawValue
        ]
        context.storedData[key] = [hintPayload]
        context.refreshHints()
    }

    static func simulateBackgroundIOSNotification(
        router: ActivityNotificationRouter,
        kind: ActivityNotificationKind
    ) {
        let event = ActivityEvent(
            kind: kind,
            title: kind == .item ? "Debug Item (Background)" : "Debug Hint (Background)",
            message: "Simulated iOS notification while app treats itself as backgrounded.",
            dedupKey: "debug:background:\(kind.rawValue):\(UUID().uuidString)"
        )
        APNotificationService.shared.withSimulatedAppInactive {
            router.deliver(event)
        }
    }

    static func simulateDisconnectNotification() {
        Task {
            await APNotificationService.shared.scheduleDebugDisconnectNotification()
        }
    }

    static func resetActivitySnapshot() {
        Persistence.saveActivitySnapshot(.empty)
    }

    static func rewindSnapshotForTesting(context: APContext) {
        let rewindCount = max(0, context.itemsReceived.count - 1)
        let hintKeys = context.hints.map(ActivityNotificationBuilder.hintKey(for:))
        let trimmedKeys = hintKeys.isEmpty ? [] : Array(hintKeys.dropLast())
        Persistence.saveActivitySnapshot(ActivitySnapshot(
            itemCount: rewindCount,
            seenHintKeys: trimmedKeys,
            updatedAt: Date()
        ))
    }

    static func clearRouterDedup(_ router: ActivityNotificationRouter) {
        router.clearRecentDeliveries()
    }

    @discardableResult
    static func scheduleNearTermBackgroundRefresh() -> Bool {
        BackgroundRefreshTask.scheduleForDebug(earliestInterval: 5)
    }
}
