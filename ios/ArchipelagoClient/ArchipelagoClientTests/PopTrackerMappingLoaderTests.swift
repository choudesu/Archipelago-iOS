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

    func testJSONCStripsBOM() throws {
        let json = "\u{FEFF}{ \"name\": \"Tunic\", \"game_name\": \"Tunic\", \"package_uid\": \"tunic\", \"package_version\": \"1\", \"variants\": {} }"
        let manifest = try JSONC.decode(PopTrackerManifest.self, from: json)
        XCTAssertEqual(manifest.name, "Tunic")
        XCTAssertEqual(manifest.packageUID, "tunic")
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

    func testVariantResolverIgnoresPersistedVariantFromDifferentPack() throws {
        let celesteManifest = PopTrackerManifest(
            name: "Celeste",
            gameName: "Celeste",
            packageUID: "celeste",
            packageVersion: "3.0.0",
            minPoptrackerVersion: nil,
            variants: [
                "standard": PopTrackerManifest.Variant(displayName: "Map Tracker", flags: ["ap"])
            ]
        )
        let variant = try PopTrackerVariantResolver.resolveVariant(
            requested: nil,
            packUID: "celeste",
            persistedPackUID: "tunic_sapphiresapphic",
            persistedVariantUID: "var_itemsonly",
            manifest: celesteManifest
        )
        XCTAssertEqual(variant, "standard")
    }

    func testVariantResolverReusesPersistedVariantForSamePack() throws {
        let tunicManifest = PopTrackerManifest(
            name: "Tunic",
            gameName: "Tunic",
            packageUID: "tunic_sapphiresapphic",
            packageVersion: "2.1.5",
            minPoptrackerVersion: nil,
            variants: [
                "standard": PopTrackerManifest.Variant(displayName: "Map Tracker", flags: ["ap"]),
                "var_itemsonly": PopTrackerManifest.Variant(displayName: "Item Tracker", flags: ["ap"])
            ]
        )
        let variant = try PopTrackerVariantResolver.resolveVariant(
            requested: nil,
            packUID: "tunic_sapphiresapphic",
            persistedPackUID: "tunic_sapphiresapphic",
            persistedVariantUID: "var_itemsonly",
            manifest: tunicManifest
        )
        XCTAssertEqual(variant, "var_itemsonly")
    }

    func testReferencedMapNamesCollectsFromNestedLocations() {
        let nodes = [
            PopTrackerLocationNode(
                name: "Area",
                children: nil,
                sections: [PopTrackerLocationSection(name: "Chest", itemCount: 1)],
                mapLocations: [
                    PopTrackerMapLocation(map: "map1", x: 10, y: 20),
                    PopTrackerMapLocation(map: "map2", x: 30, y: 40)
                ]
            ),
            PopTrackerLocationNode(
                name: "Other",
                children: [
                    PopTrackerLocationNode(
                        name: "Child",
                        children: nil,
                        sections: [PopTrackerLocationSection(name: "Secret", itemCount: 1)],
                        mapLocations: [PopTrackerMapLocation(map: "map3", x: 1, y: 2)]
                    )
                ],
                sections: nil,
                mapLocations: nil
            )
        ]
        XCTAssertEqual(
            PopTrackerPackLoader.referencedMapNames(from: nodes),
            Set(["map1", "map2", "map3"])
        )
    }

    func testDisplayableMapsFiltersUnreferencedPlaceholders() {
        let pack = PopTrackerLoadedPack(
            install: PopTrackerInstalledPack(
                packageUID: "outer_wilds",
                name: "Outer Wilds",
                gameName: "Outer Wilds",
                packageVersion: "1.0.0",
                installedAt: Date(),
                variants: ["standard"]
            ),
            rootURL: URL(fileURLWithPath: "/tmp"),
            manifest: PopTrackerManifest(
                name: "Outer Wilds",
                gameName: "Outer Wilds",
                packageUID: "outer_wilds",
                packageVersion: "1.0.0",
                minPoptrackerVersion: nil,
                variants: ["standard": PopTrackerManifest.Variant(displayName: "Items", flags: ["ap"])]
            ),
            variantUID: "standard",
            items: [],
            locations: [],
            maps: [
                PopTrackerMapDefinition(name: "map1", img: "images/map1.png", locationSize: nil),
                PopTrackerMapDefinition(name: "map2", img: "images/map2.png", locationSize: nil)
            ],
            itemMapping: [:],
            locationMapping: [:],
            sectionPaths: [],
            sectionPathByAPLocationID: [:]
        )
        XCTAssertTrue(pack.displayableMaps.isEmpty)
    }

    func testDisplayableMapsKeepsReferencedMaps() {
        let pack = PopTrackerLoadedPack(
            install: PopTrackerInstalledPack(
                packageUID: "celeste",
                name: "Celeste",
                gameName: "Celeste",
                packageVersion: "3.0.0",
                installedAt: Date(),
                variants: ["standard"]
            ),
            rootURL: URL(fileURLWithPath: "/tmp"),
            manifest: PopTrackerManifest(
                name: "Celeste",
                gameName: "Celeste",
                packageUID: "celeste",
                packageVersion: "3.0.0",
                minPoptrackerVersion: nil,
                variants: ["standard": PopTrackerManifest.Variant(displayName: "Map Tracker", flags: ["ap"])]
            ),
            variantUID: "standard",
            items: [],
            locations: [
                PopTrackerLocationNode(
                    name: "Prologue",
                    children: nil,
                    sections: [PopTrackerLocationSection(name: "Chest", itemCount: 1)],
                    mapLocations: [PopTrackerMapLocation(map: "00_prologue", x: 1, y: 2)]
                )
            ],
            maps: [
                PopTrackerMapDefinition(name: "00_prologue", img: "images/00_prologue.png", locationSize: 16),
                PopTrackerMapDefinition(name: "01_forsaken", img: "images/01_forsaken.png", locationSize: 16)
            ],
            itemMapping: [:],
            locationMapping: [:],
            sectionPaths: ["Prologue/Chest"],
            sectionPathByAPLocationID: [:]
        )
        XCTAssertEqual(pack.displayableMaps.map(\.name), ["00_prologue"])
    }
}
