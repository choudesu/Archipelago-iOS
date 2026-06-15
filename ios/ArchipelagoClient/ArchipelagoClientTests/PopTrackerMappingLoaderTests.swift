import XCTest
@testable import ArchipelagoClient

final class PopTrackerMappingLoaderTests: XCTestCase {
    func testParsesLocationMappingWithBaseID() {
        let lua = """
        BASE_LOCATION_ID = 1000
        LOCATION_MAPPING = {
            [BASE_LOCATION_ID + 1] = { { "@Dungeon/Chest" } },
            [BASE_LOCATION_ID + 2] = { { "toggle" } },
        }
        """
        let mapping = PopTrackerMappingLoader.parseMappingTable(
            named: "LOCATION_MAPPING",
            in: lua,
            baseID: PopTrackerMappingLoader.parseBaseID(named: "BASE_LOCATION_ID", in: lua)
        )
        XCTAssertEqual(mapping[1001], ["Dungeon/Chest"])
        XCTAssertEqual(mapping[1002], ["toggle"])
    }

    func testParsesItemMappingWithMultipleCodes() {
        let lua = """
        BASE_ITEM_ID = 0
        ITEM_MAPPING = {
            [BASE_ITEM_ID + 4] = { { "toggle" }, { "consumable" } },
        }
        """
        let mapping = PopTrackerMappingLoader.parseMappingTable(
            named: "ITEM_MAPPING",
            in: lua,
            baseID: 0
        )
        XCTAssertEqual(mapping[4], ["toggle", "consumable"])
    }

    func testJSONCStripsLineComments() throws {
        let json = """
        [
          // comment
          { "name": "A", "type": "toggle", "codes": "a" }
        ]
        """
        let items = try JSONC.decode([PopTrackerPackItem].self, from: json)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].name, "A")
    }

    func testBuildSectionPaths() {
        let nodes = [
            PopTrackerLocationNode(
                name: "Parent",
                children: [
                    PopTrackerLocationNode(
                        name: "Child",
                        children: nil,
                        sections: [PopTrackerLocationSection(name: "Chest", itemCount: 1)],
                        mapLocations: nil
                    )
                ],
                sections: nil,
                mapLocations: nil
            )
        ]
        XCTAssertEqual(PopTrackerPackLoader.buildSectionPaths(nodes), ["Parent/Child/Chest"])
    }
}
