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
}
