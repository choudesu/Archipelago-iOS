import Foundation
import SwiftUI

struct JSONMessageRenderer {
    let playerNames: [Int: String]
    let nameLookup: NameLookup
    let slot: Int?
    let slotInfo: [Int: NetworkSlot]
    let slotConcernsSelf: (Int) -> Bool
    let palette: APArchipelagoColors.Palette

    init(
        playerNames: [Int: String],
        nameLookup: NameLookup,
        slot: Int?,
        slotInfo: [Int: NetworkSlot],
        slotConcernsSelf: @escaping (Int) -> Bool,
        colorScheme: ColorScheme = .dark
    ) {
        self.playerNames = playerNames
        self.nameLookup = nameLookup
        self.slot = slot
        self.slotInfo = slotInfo
        self.slotConcernsSelf = slotConcernsSelf
        self.palette = APArchipelagoColors.palette(for: colorScheme)
    }

    func render(_ parts: [JSONMessagePart]) -> String {
        String(renderAttributed(parts).characters)
    }

    func renderAttributed(_ parts: [JSONMessagePart]) -> AttributedString {
        var result = AttributedString()
        for part in parts {
            result.append(renderAttributedPart(part))
        }
        return result
    }

    private func renderAttributedPart(_ part: JSONMessagePart) -> AttributedString {
        switch part.type {
        case "player_id":
            let player = Int(part.text ?? "0") ?? 0
            let text = playerNames[player] ?? "Player \(player)"
            return coloredSegment(text, color: palette.playerColor(isSelf: slotConcernsSelf(player)))
        case "player_name":
            return coloredSegment(part.text ?? "", color: palette.yellow)
        case "item_id":
            let itemID = Int(part.text ?? "0") ?? 0
            let player = part.player ?? 0
            let text = nameLookup.lookupItemInSlot(itemID, slot: player, slotInfo: slotInfo)
            return coloredSegment(text, color: palette.itemColor(flags: part.flags ?? 0))
        case "item_name":
            return coloredSegment(part.text ?? "", color: palette.itemColor(flags: part.flags ?? 0))
        case "location_id":
            let locationID = Int(part.text ?? "0") ?? 0
            let player = part.player ?? 0
            let text = nameLookup.lookupLocationInSlot(locationID, slot: player, slotInfo: slotInfo)
            return coloredSegment(text, color: palette.green)
        case "location_name":
            return coloredSegment(part.text ?? "", color: palette.green)
        case "entrance_name":
            return coloredSegment(part.text ?? "", color: palette.blue)
        case "hint_status":
            let text: String
            let color: Color
            if let status = part.hintStatus, let hint = HintStatus(rawValue: status) {
                text = hint.displayName
                color = palette.hintStatusColor(hint)
            } else {
                text = part.text ?? ""
                color = palette.red
            }
            return coloredSegment(text, color: color)
        case "color":
            let text = part.text ?? ""
            let color = part.color.flatMap { palette.color(fromSemicolonList: $0) }
            return coloredSegment(text, color: color)
        default:
            return AttributedString(part.text ?? "")
        }
    }

    private func coloredSegment(_ text: String, color: Color?) -> AttributedString {
        var segment = AttributedString(text)
        if let color {
            segment.foregroundColor = color
        }
        return segment
    }
}
