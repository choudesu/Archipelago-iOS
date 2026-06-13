import Foundation
import SwiftUI

@MainActor
enum APNotificationFilter {
    private static let systemTypes: Set<String> = [
        "Join", "Part", "Goal", "Release", "Collect",
        "Countdown", "Tutorial", "ServerChat", "CommandResult", "Hint"
    ]

    static func isEchoedChat(_ args: [String: Any], team: Int?, slot: Int?) -> Bool {
        guard (args["type"] as? String) == "Chat" else { return false }
        guard let messageTeam = args["team"] as? Int,
              let messageSlot = args["slot"] as? Int,
              let team, let slot else {
            return false
        }
        return messageTeam == team && messageSlot == slot
    }

    static func concernsReceivingPlayer(
        _ args: [String: Any],
        slotConcernsSelf: (Int) -> Bool
    ) -> Bool {
        guard (args["type"] as? String) == "ItemSend",
              let receiving = args["receiving"] as? Int else {
            return false
        }
        return slotConcernsSelf(receiving)
    }

    static func shouldNotifyChat(_ args: [String: Any], context: APContext) -> Bool {
        guard (args["type"] as? String) == "Chat" else { return false }
        guard !isEchoedChat(args, team: context.team, slot: context.slot) else { return false }
        let parts = decodeMessageParts(args["data"])
        let body = parts.compactMap(\.text).joined()
        return !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func shouldNotifyPrintJSON(_ args: [String: Any], context: APContext) -> Bool {
        shouldNotifyChat(args, context: context)
    }

    static func chatNotificationTitle(_ args: [String: Any], context: APContext) -> String {
        if let slot = args["slot"] as? Int,
           let name = context.playerNames[slot] {
            return name
        }
        return "Archipelago Chat"
    }

    static func chatNotificationBody(_ args: [String: Any], context: APContext) -> String {
        let parts = decodeMessageParts(args["data"])
        let renderer = JSONMessageRenderer(
            playerNames: context.playerNames,
            nameLookup: context.nameLookup,
            slot: context.slot,
            slotInfo: context.slotInfo,
            slotConcernsSelf: context.slotConcernsSelf
        )
        return renderer.render(parts)
    }

    static func itemNotificationTitle(_ item: NetworkItem) -> String {
        item.flags & 0b100 != 0 ? "Trap Received" : "Item Received"
    }

    static func itemNotificationBody(_ item: NetworkItem, context: APContext) -> String {
        let itemName = context.nameLookup.lookupItemInSlot(
            item.item,
            slot: item.player,
            slotInfo: context.slotInfo
        )
        let locationName = context.nameLookup.lookupLocationInSlot(
            item.location,
            slot: item.player,
            slotInfo: context.slotInfo
        )
        let finderName = context.playerNames[item.player] ?? "Player \(item.player)"

        if item.flags & 0b100 != 0 {
            return "Trap: \(itemName) from \(finderName) (\(locationName))"
        }
        return "Received \(itemName) from \(finderName)'s world (\(locationName))"
    }

    private static func decodeMessageParts(_ value: Any?) -> [JSONMessagePart] {
        guard let array = value as? [[String: Any]] else { return [] }
        return array.compactMap { dict in
            try? JSONDecoder().decode(JSONMessagePart.self, from: JSONSerialization.data(withJSONObject: dict))
        }
    }
}
