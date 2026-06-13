import SwiftUI
import XCTest
@testable import ArchipelagoClient

final class JSONMessageRendererTests: XCTestCase {
    private let package = GamesPackage(
        itemNameToID: ["Plasma Rifle": 56061, "Trap Item": 99],
        locationNameToID: ["E1M1": 100],
        itemNameGroups: nil,
        locationNameGroups: nil,
        checksum: nil
    )

    private lazy var lookup: NameLookup = {
        let lookup = NameLookup()
        lookup.updateGame(package, game: "DOOM 1993")
        return lookup
    }()

    private let slotInfo: [Int: NetworkSlot] = [
        5: NetworkSlot(name: "Doom V", game: "DOOM 1993", type: SlotType.player.rawValue)
    ]

    private func makeRenderer(
        slot: Int? = 5,
        slotConcernsSelf: @escaping (Int) -> Bool = { $0 == 5 }
    ) -> JSONMessageRenderer {
        JSONMessageRenderer(
            playerNames: [5: "Doom V", 7: "Other Player"],
            nameLookup: lookup,
            slot: slot,
            slotInfo: slotInfo,
            slotConcernsSelf: slotConcernsSelf
        )
    }

    private func decodeParts(_ json: String) throws -> [JSONMessagePart] {
        try JSONDecoder().decode([JSONMessagePart].self, from: Data(json.utf8))
    }

    private func foregroundColor(of substring: String, in attributed: AttributedString) -> Color? {
        guard let range = attributed.range(of: substring) else {
            return nil
        }
        return attributed[range].foregroundColor ?? attributed.runs[range].foregroundColor
    }

    func testProgressionItemUsesPlumColor() throws {
        let parts = try decodeParts(#"[{"text":"56061","player":5,"flags":1,"type":"item_id"}]"#)
        let attributed = makeRenderer().renderAttributed(parts)

        XCTAssertEqual(String(attributed.characters), "Plasma Rifle")
        XCTAssertEqual(foregroundColor(of: "Plasma Rifle", in: attributed), APArchipelagoColors.plum)
    }

    func testRegularItemUsesCyanColor() throws {
        let parts = try decodeParts(#"[{"text":"56061","player":5,"flags":0,"type":"item_id"}]"#)
        let attributed = makeRenderer().renderAttributed(parts)

        XCTAssertEqual(String(attributed.characters), "Plasma Rifle")
        XCTAssertEqual(foregroundColor(of: "Plasma Rifle", in: attributed), APArchipelagoColors.cyan)
    }

    func testLocationUsesGreenColor() throws {
        let parts = try decodeParts(#"[{"text":"100","player":5,"type":"location_id"}]"#)
        let attributed = makeRenderer().renderAttributed(parts)

        XCTAssertEqual(String(attributed.characters), "E1M1")
        XCTAssertEqual(foregroundColor(of: "E1M1", in: attributed), APArchipelagoColors.green)
    }

    func testOwnPlayerUsesMagentaColor() throws {
        let parts = try decodeParts(#"[{"text":"5","type":"player_id"}]"#)
        let attributed = makeRenderer().renderAttributed(parts)

        XCTAssertEqual(String(attributed.characters), "Doom V")
        XCTAssertEqual(foregroundColor(of: "Doom V", in: attributed), APArchipelagoColors.magenta)
    }

    func testOtherPlayerUsesYellowColor() throws {
        let parts = try decodeParts(#"[{"text":"7","type":"player_id"}]"#)
        let attributed = makeRenderer().renderAttributed(parts)

        XCTAssertEqual(String(attributed.characters), "Other Player")
        XCTAssertEqual(foregroundColor(of: "Other Player", in: attributed), APArchipelagoColors.yellow)
    }

    func testHintStatusUsesExpectedColor() throws {
        let parts = try decodeParts(#"[{"text":"(priority)","hint_status":30,"type":"hint_status"}]"#)
        let attributed = makeRenderer().renderAttributed(parts)

        XCTAssertEqual(String(attributed.characters), "(priority)")
        XCTAssertEqual(foregroundColor(of: "(priority)", in: attributed), APArchipelagoColors.plum)
    }

    func testLightPaletteImprovesContrastOnWhiteBackground() {
        let darkYellow = APArchipelagoColors.rgbHex(APArchipelagoColors.dark.yellow)
        let lightYellow = APArchipelagoColors.rgbHex(APArchipelagoColors.light.yellow)
        let darkCyan = APArchipelagoColors.rgbHex(APArchipelagoColors.dark.cyan)
        let lightCyan = APArchipelagoColors.rgbHex(APArchipelagoColors.light.cyan)

        XCTAssertNotEqual(darkYellow, lightYellow)
        XCTAssertNotEqual(darkCyan, lightCyan)
        XCTAssertEqual(lightYellow, "8B7500")
        XCTAssertEqual(lightCyan, "007A7A")
    }

    func testLightModeRendererUsesReadablePlayerColors() throws {
        let parts = try decodeParts(#"[{"text":"7","type":"player_id"}]"#)
        let renderer = JSONMessageRenderer(
            playerNames: [7: "Other Player"],
            nameLookup: lookup,
            slot: 5,
            slotInfo: slotInfo,
            slotConcernsSelf: { $0 == 5 },
            colorScheme: .light
        )
        let attributed = renderer.renderAttributed(parts)

        XCTAssertEqual(foregroundColor(of: "Other Player", in: attributed), APArchipelagoColors.light.yellow)
    }

    func testRenderPlainStringMatchesAttributedOutput() throws {
        let parts = try decodeParts(
            #"[
                {"text":"[","type":"text"},
                {"text":"5","type":"player_id"},
                {"text":"] found ","type":"text"},
                {"text":"56061","player":5,"flags":0,"type":"item_id"},
                {"text":" at ","type":"text"},
                {"text":"100","player":5,"type":"location_id"}
            ]"#
        )
        let renderer = makeRenderer()
        XCTAssertEqual(renderer.render(parts), String(renderer.renderAttributed(parts).characters))
    }
}
