import XCTest
@testable import ArchipelagoClient

@MainActor
final class ActivityDebugServiceTests: XCTestCase {
    private var context: APContext!
    private var inAppCenter: InAppNotificationCenter!
    private var router: ActivityNotificationRouter!

    override func setUp() {
        super.setUp()
        context = APContext()
        context.slot = 2
        context.team = 0
        context.setSlotName("DebugSlot")
        inAppCenter = InAppNotificationCenter()
        router = ActivityNotificationRouter(inAppCenter: inAppCenter)
        context.activityRouter = router
        Persistence.debugModeEnabled = true
        Persistence.activityAlertsEnabled = true
        router.clearRecentDeliveries()
    }

    override func tearDown() {
        Persistence.debugModeEnabled = false
        Persistence.saveActivitySnapshot(.empty)
        super.tearDown()
    }

    func testSimulateItemAlertPostsInAppBannerWhenActive() {
        let event = ActivityDebugService.simulateItemAlert(context: context, router: router)
        XCTAssertEqual(event.kind, .item)
        XCTAssertFalse(inAppCenter.active.isEmpty)
    }

    func testSimulatedInactiveSkipsInAppBanner() {
        APNotificationService.shared.withSimulatedAppInactive {
            ActivityDebugService.simulateItemAlert(
                context: context,
                router: router,
                itemID: 50,
                locationID: 51
            )
        }
        XCTAssertTrue(inAppCenter.active.isEmpty)
    }

    func testReceivedItemsPathIncrementsCount() {
        let before = context.itemsReceived.count
        ActivityDebugService.simulateReceivedItemsPath(context: context, itemID: 42, locationID: 84)
        XCTAssertEqual(context.itemsReceived.count, before + 1)
    }

    func testRewindSnapshotSetsLowerItemCount() {
        context.itemsReceived = [
            NetworkItem(item: 1, location: 2, player: 2, flags: 0),
            NetworkItem(item: 3, location: 4, player: 2, flags: 0)
        ]
        ActivityDebugService.rewindSnapshotForTesting(context: context)
        let snapshot = Persistence.loadActivitySnapshot()
        XCTAssertEqual(snapshot.itemCount, 1)
    }

    func testResetActivitySnapshotClearsState() {
        Persistence.saveActivitySnapshot(ActivitySnapshot(
            itemCount: 5,
            seenHintKeys: ["hint:1:2:3:4"],
            updatedAt: Date()
        ))
        ActivityDebugService.resetActivitySnapshot()
        let snapshot = Persistence.loadActivitySnapshot()
        XCTAssertEqual(snapshot.itemCount, 0)
        XCTAssertTrue(snapshot.seenHintKeys.isEmpty)
    }

    func testStatusReflectsContextCounts() {
        context.itemsReceived = [NetworkItem(item: 1, location: 2, player: 2, flags: 0)]
        let status = ActivityDebugService.status(for: context)
        XCTAssertEqual(status.liveItemCount, 1)
        XCTAssertEqual(status.slot, 2)
    }

    func testRouterDedupPreventsDuplicateBanner() {
        ActivityDebugService.simulateItemAlert(
            context: context,
            router: router,
            itemID: 99,
            locationID: 100
        )
        let firstCount = inAppCenter.active.count
        ActivityDebugService.simulateItemAlert(
            context: context,
            router: router,
            itemID: 99,
            locationID: 100
        )
        XCTAssertEqual(inAppCenter.active.count, firstCount)
    }

    func testClearRouterDedupAllowsRepeatDelivery() {
        ActivityDebugService.simulateItemAlert(
            context: context,
            router: router,
            itemID: 7,
            locationID: 8
        )
        ActivityDebugService.clearRouterDedup(router)
        ActivityDebugService.simulateItemAlert(
            context: context,
            router: router,
            itemID: 7,
            locationID: 8
        )
        XCTAssertGreaterThanOrEqual(inAppCenter.active.count, 1)
    }
}
