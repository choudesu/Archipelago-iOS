import XCTest
@testable import ArchipelagoClient

@MainActor
final class APNotificationFilterTests: XCTestCase {
    private func makeContext(team: Int = 1, slot: Int = 5) -> APContext {
        let context = APContext()
        context.team = team
        context.slot = slot
        context.playerNames = [
            5: "Doom V",
            7: "Other Player"
        ]
        let package = GamesPackage(
            itemNameToID: ["Plasma Rifle": 56061, "Quake Trap": 99],
            locationNameToID: ["E1M1": 100],
            itemNameGroups: nil,
            locationNameGroups: nil,
            checksum: nil
        )
        context.nameLookup.updateGame(package, game: "DOOM 1993")
        context.slotInfo = [
            5: NetworkSlot(name: "Doom V", game: "DOOM 1993", type: SlotType.player.rawValue),
            7: NetworkSlot(name: "Other Player", game: "DOOM 1993", type: SlotType.player.rawValue)
        ]
        return context
    }

    func testChatFromOtherPlayerShouldNotify() {
        let context = makeContext()
        let args: [String: Any] = [
            "type": "Chat",
            "team": 1,
            "slot": 7,
            "message": "hello",
            "data": [["text": "Other Player: hello"]]
        ]
        XCTAssertTrue(APNotificationFilter.shouldNotifyChat(args, context: context))
    }

    func testEchoedChatShouldNotNotify() {
        let context = makeContext()
        let args: [String: Any] = [
            "type": "Chat",
            "team": 1,
            "slot": 5,
            "message": "hello",
            "data": [["text": "Doom V: hello"]]
        ]
        XCTAssertFalse(APNotificationFilter.shouldNotifyChat(args, context: context))
    }

    func testJoinMessageShouldNotNotify() {
        let context = makeContext()
        let args: [String: Any] = [
            "type": "Join",
            "team": 1,
            "slot": 7,
            "data": [["text": "Other Player has joined"]]
        ]
        XCTAssertFalse(APNotificationFilter.shouldNotifyPrintJSON(args, context: context))
    }

    func testCommandResultShouldNotNotify() {
        let context = makeContext()
        let args: [String: Any] = [
            "type": "CommandResult",
            "data": [["text": "Hint cost is 10%"]]
        ]
        XCTAssertFalse(APNotificationFilter.shouldNotifyPrintJSON(args, context: context))
    }

    func testItemSendForOtherReceivingPlayerDoesNotConcernSelf() {
        let context = makeContext()
        let args: [String: Any] = [
            "type": "ItemSend",
            "receiving": 7,
            "item": NetworkItem(item: 56061, location: 100, player: 5, flags: 0)
        ]
        XCTAssertFalse(APNotificationFilter.concernsReceivingPlayer(args) { context.slotConcernsSelf($0) })
    }

    func testItemSendForSelfConcernsReceivingPlayer() {
        let context = makeContext()
        let args: [String: Any] = [
            "type": "ItemSend",
            "receiving": 5,
            "item": NetworkItem(item: 56061, location: 100, player: 7, flags: 0)
        ]
        XCTAssertTrue(APNotificationFilter.concernsReceivingPlayer(args) { context.slotConcernsSelf($0) })
    }

    func testRegularItemNotificationBody() {
        let context = makeContext()
        let item = NetworkItem(item: 56061, location: 100, player: 7, flags: 0)
        XCTAssertEqual(APNotificationFilter.itemNotificationTitle(item), "Item Received")
        XCTAssertEqual(
            APNotificationFilter.itemNotificationBody(item, context: context),
            "Received Plasma Rifle from Other Player's world (E1M1)"
        )
    }

    func testTrapItemNotificationBody() {
        let context = makeContext()
        let item = NetworkItem(item: 99, location: 100, player: 7, flags: 0b100)
        XCTAssertEqual(APNotificationFilter.itemNotificationTitle(item), "Trap Received")
        XCTAssertEqual(
            APNotificationFilter.itemNotificationBody(item, context: context),
            "Trap: Quake Trap from Other Player (E1M1)"
        )
    }
}
