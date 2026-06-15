import XCTest
@testable import ArchipelagoClient

@MainActor
final class APContextTrackerTests: XCTestCase {
    private var context: APContext!

    override func setUp() {
        super.setUp()
        context = APContext()
        context.applyClientMode(.tracker)
    }

    func testTrackerModeSetsTagsAndSlotData() {
        XCTAssertEqual(context.tags, ClientMode.tracker.tags)
        XCTAssertTrue(context.wantSlotData)
    }

    func testTextModeSetsTextOnlyTag() {
        context.applyClientMode(.text)
        XCTAssertEqual(context.tags, ClientMode.text.tags)
        XCTAssertFalse(context.wantSlotData)
    }

    func testCheckLocationsOnlySendsMissing() async {
        context.missingLocations = [10, 20, 30]
        let sent = await context.checkLocations([10, 99])
        XCTAssertEqual(sent, [10])
        XCTAssertTrue(context.locationsChecked.contains(10))
        XCTAssertFalse(context.locationsChecked.contains(99))
    }

    func testScoutLocationsOnlySendsMissing() async {
        context.missingLocations = [5, 6]
        let sent = await context.scoutLocations([5, 7], asHint: true)
        XCTAssertEqual(sent, [5])
        XCTAssertTrue(context.locationsScouted.contains(5))
    }

    func testMergeCheckedLocationsFromRoomUpdate() {
        context.missingLocations = [1, 2, 3]
        context.checkedLocations = []
        context.mergeCheckedLocations([2, 3])
        XCTAssertEqual(context.checkedLocations, [2, 3])
        XCTAssertEqual(context.missingLocations, [1])
    }
}
