import Foundation

struct JSONMessageRenderer {
    let playerNames: [Int: String]
    let nameLookup: NameLookup
    let slot: Int?
    let slotInfo: [Int: NetworkSlot]

    func render(_ parts: [JSONMessagePart]) -> String {
        parts.map { renderPart($0) }.joined()
    }

    private func renderPart(_ part: JSONMessagePart) -> String {
        switch part.type {
        case "player_id":
            let player = Int(part.text ?? "0") ?? 0
            return playerNames[player] ?? "Player \(player)"
        case "item_id":
            let itemID = Int(part.text ?? "0") ?? 0
            let player = part.player ?? 0
            return nameLookup.lookupItemInSlot(itemID, slot: player, slotInfo: slotInfo)
        case "location_id":
            let locationID = Int(part.text ?? "0") ?? 0
            let player = part.player ?? 0
            return nameLookup.lookupLocationInSlot(locationID, slot: player, slotInfo: slotInfo)
        case "hint_status":
            if let status = part.hintStatus, let hint = HintStatus(rawValue: status) {
                return hint.displayName
            }
            return part.text ?? ""
        default:
            return part.text ?? ""
        }
    }
}
