import XCTest
@testable import ArchipelagoClient

final class NameLookupTests: XCTestCase {
    func testLookupUsesCachedDataPackageWithoutNetworkFetch() {
        let package = GamesPackage(
            itemNameToID: ["Plasma Rifle": 56061],
            locationNameToID: ["E1M1": 100],
            itemNameGroups: nil,
            locationNameGroups: nil,
            checksum: nil
        )
        DataPackageCache.shared.store(package: package, game: "DOOM 1993")

        let lookup = NameLookup()
        lookup.updateGame(package, game: "DOOM 1993")

        let slotInfo: [Int: NetworkSlot] = [
            5: NetworkSlot(name: "Doom V", game: "DOOM 1993", type: SlotType.player.rawValue)
        ]

        XCTAssertEqual(
            lookup.lookupItemInSlot(56061, slot: 5, slotInfo: slotInfo),
            "Plasma Rifle"
        )
        XCTAssertEqual(
            lookup.lookupLocationInSlot(100, slot: 5, slotInfo: slotInfo),
            "E1M1"
        )
    }

    func testJSONMessagePartDecodesNumericText() throws {
        let json = """
        [{"text":56061,"player":5,"type":"item_id"}]
        """
        let data = try JSONDecoder().decode([JSONMessagePart].self, from: Data(json.utf8))
        XCTAssertEqual(data.count, 1)
        XCTAssertEqual(data[0].text, "56061")
        XCTAssertEqual(data[0].player, 5)
        XCTAssertEqual(data[0].type, "item_id")
    }

    func testLookupRequiresSlotInfoGame() {
        let lookup = NameLookup()
        let package = GamesPackage(
            itemNameToID: ["Monster Candy": 8577001],
            locationNameToID: ["Ruins - Dummy Check": 509342640],
            itemNameGroups: nil,
            locationNameGroups: nil,
            checksum: nil
        )
        lookup.updateGame(package, game: "Undertale")

        let slotInfo: [Int: NetworkSlot] = [
            12: NetworkSlot(name: "viruMon47", game: "Undertale", type: SlotType.player.rawValue),
            34: NetworkSlot(name: "viruTunic50", game: "TUNIC", type: SlotType.player.rawValue)
        ]

        XCTAssertEqual(lookup.lookupItemInSlot(8577001, slot: 12, slotInfo: slotInfo), "Monster Candy")
        XCTAssertEqual(lookup.lookupLocationInSlot(509342640, slot: 34, slotInfo: slotInfo), "Ruins - Dummy Check")
        XCTAssertEqual(lookup.lookupItemInSlot(8577001, slot: 12, slotInfo: [:]), "Unknown item (ID: 8577001)")
    }

    func testNetworkSlotParsesDecodedTypedValue() {
        let slot = NetworkSlot(name: "Doom I", game: "DOOM II", type: SlotType.player.rawValue)
        XCTAssertEqual(NetworkSlot.parseDecodedValue(slot)?.game, "DOOM II")
    }

    func testGamesPackageParsesLargeIDsFromNSDictionaryStylePayload() {
        let payload: [String: Any] = [
            "item_name_to_id": ["Armor": NSNumber(value: 8577001)],
            "location_name_to_id": ["MAP29 Chest": NSNumber(value: 509342640)]
        ]
        let package = GamesPackage.parse(gameData: payload)
        XCTAssertEqual(package?.itemNameToID["Armor"], 8577001)
        XCTAssertEqual(package?.locationNameToID["MAP29 Chest"], 509342640)
    }
}
