import XCTest
@testable import ArchipelagoClient

final class ActivityNotificationBuilderTests: XCTestCase {
    func testHintInvolvesSelfForReceivingPlayer() {
        XCTAssertTrue(ActivityNotificationBuilder.hintInvolvesSelf(
            receivingPlayer: 2,
            findingPlayer: 5,
            slotConcernsSelf: { $0 == 2 }
        ))
    }

    func testHintInvolvesSelfForFindingPlayer() {
        XCTAssertTrue(ActivityNotificationBuilder.hintInvolvesSelf(
            receivingPlayer: 5,
            findingPlayer: 2,
            slotConcernsSelf: { $0 == 2 }
        ))
    }

    func testHintDoesNotInvolveUnrelatedPlayer() {
        XCTAssertFalse(ActivityNotificationBuilder.hintInvolvesSelf(
            receivingPlayer: 3,
            findingPlayer: 4,
            slotConcernsSelf: { $0 == 2 }
        ))
    }

    func testHintDedupKeyIsStable() {
        let key = ActivityNotificationBuilder.hintDedupKey(
            findingPlayer: 1,
            location: 100,
            item: 200,
            receivingPlayer: 2
        )
        XCTAssertEqual(key, "hint:1:100:200:2")
    }

    func testItemDedupKeyIsStable() {
        let item = NetworkItem(item: 10, location: 20, player: 1, flags: 0)
        XCTAssertEqual(ActivityNotificationBuilder.itemDedupKey(item: item), "item:10:20:1")
    }

    func testItemEventUsesResolvedNames() {
        let lookup = NameLookup()
        let package: [String: Any] = [
            "item_name_to_id": ["Sword": 10],
            "location_name_to_id": ["Cave": 20]
        ]
        lookup.updateGame(package, game: "TestGame")

        let slotInfo: [Int: NetworkSlot] = [
            1: NetworkSlot(name: "Player1", game: "TestGame", type: SlotType.player.rawValue)
        ]
        let item = NetworkItem(item: 10, location: 20, player: 1, flags: 0)
        let event = ActivityNotificationBuilder.itemEvent(
            item: item,
            nameLookup: lookup,
            playerNames: [1: "Alice"],
            slotInfo: slotInfo
        )

        XCTAssertEqual(event.kind, .item)
        XCTAssertEqual(event.title, "Item Received")
        XCTAssertTrue(event.message.contains("Sword"))
        XCTAssertTrue(event.message.contains("Cave"))
        XCTAssertTrue(event.message.contains("Alice"))
    }

    func testActivitySnapshotRoundTrip() {
        let snapshot = ActivitySnapshot(
            itemCount: 3,
            seenHintKeys: ["hint:1:2:3:4"],
            updatedAt: Date(timeIntervalSince1970: 1_000)
        )
        Persistence.saveActivitySnapshot(snapshot)
        let loaded = Persistence.loadActivitySnapshot()
        XCTAssertEqual(loaded.itemCount, 3)
        XCTAssertEqual(loaded.seenHintKeys, ["hint:1:2:3:4"])
    }
}
