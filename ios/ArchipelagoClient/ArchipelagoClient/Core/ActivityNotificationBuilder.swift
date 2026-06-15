import Foundation

enum ActivityNotificationKind: String, Equatable, Sendable {
    case item
    case hint
}

struct ActivityEvent: Equatable, Sendable {
    let kind: ActivityNotificationKind
    let title: String
    let message: String
    let dedupKey: String
}

enum ActivityNotificationBuilder {
    static func hintDedupKey(
        findingPlayer: Int,
        location: Int,
        item: Int,
        receivingPlayer: Int
    ) -> String {
        "hint:\(findingPlayer):\(location):\(item):\(receivingPlayer)"
    }

    static func itemDedupKey(item: NetworkItem) -> String {
        "item:\(item.item):\(item.location):\(item.player)"
    }

    static func hintInvolvesSelf(
        receivingPlayer: Int,
        findingPlayer: Int,
        slotConcernsSelf: (Int) -> Bool
    ) -> Bool {
        slotConcernsSelf(receivingPlayer) || slotConcernsSelf(findingPlayer)
    }

    static func hintKey(for hint: HintEntry) -> String {
        hintDedupKey(
            findingPlayer: hint.findingPlayer,
            location: hint.location,
            item: hint.item,
            receivingPlayer: hint.receivingPlayer
        )
    }

    static func itemEvent(
        item: NetworkItem,
        nameLookup: NameLookup,
        playerNames: [Int: String],
        slotInfo: [Int: NetworkSlot],
        sessionLabel: String? = nil
    ) -> ActivityEvent {
        let itemName = nameLookup.lookupItemInSlot(item.item, slot: item.player, slotInfo: slotInfo)
        let locationName = nameLookup.lookupLocationInSlot(item.location, slot: item.player, slotInfo: slotInfo)
        let sender = playerNames[item.player] ?? "Player \(item.player)"
        let title = sessionLabel.map { "Item Received · \($0)" } ?? "Item Received"
        return ActivityEvent(
            kind: .item,
            title: title,
            message: "\(itemName) from \(locationName) by \(sender)",
            dedupKey: itemDedupKey(item: item)
        )
    }

    static func hintEvent(
        hint: HintEntry,
        nameLookup: NameLookup,
        playerNames: [Int: String],
        slotInfo: [Int: NetworkSlot],
        sessionLabel: String? = nil
    ) -> ActivityEvent {
        let itemName = nameLookup.lookupItemInSlot(hint.item, slot: hint.receivingPlayer, slotInfo: slotInfo)
        let locationName = nameLookup.lookupLocationInSlot(hint.location, slot: hint.findingPlayer, slotInfo: slotInfo)
        let finder = playerNames[hint.findingPlayer] ?? "Player \(hint.findingPlayer)"
        let receiver = playerNames[hint.receivingPlayer] ?? "Player \(hint.receivingPlayer)"
        var message = "\(itemName) at \(locationName) (\(finder) → \(receiver))"
        if !hint.entrance.isEmpty {
            message += " · \(hint.entrance)"
        }
        let title = sessionLabel.map { "New Hint · \($0)" } ?? "New Hint"
        return ActivityEvent(
            kind: .hint,
            title: title,
            message: message,
            dedupKey: hintKey(for: hint)
        )
    }

    static func hintEvent(
        receivingPlayer: Int,
        findingPlayer: Int,
        itemID: Int,
        locationID: Int,
        itemFlags: Int,
        entrance: String,
        nameLookup: NameLookup,
        playerNames: [Int: String],
        slotInfo: [Int: NetworkSlot],
        sessionLabel: String? = nil
    ) -> ActivityEvent {
        let hint = HintEntry(from: [
            "receiving_player": receivingPlayer,
            "finding_player": findingPlayer,
            "location": locationID,
            "item": itemID,
            "item_flags": itemFlags,
            "entrance": entrance,
            "found": false,
            "status": HintStatus.unspecified.rawValue
        ])
        return hintEvent(
            hint: hint,
            nameLookup: nameLookup,
            playerNames: playerNames,
            slotInfo: slotInfo,
            sessionLabel: sessionLabel
        )
    }
}

struct ActivitySnapshot: Codable, Equatable {
    var itemCount: Int
    var seenHintKeys: [String]
    var updatedAt: Date

    static let empty = ActivitySnapshot(itemCount: 0, seenHintKeys: [], updatedAt: .distantPast)
}
