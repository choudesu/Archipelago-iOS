import XCTest
@testable import ArchipelagoClient

@MainActor
final class APNotificationServiceTests: XCTestCase {
    override func setUp() {
        super.setUp()
        Persistence.notificationsEnabled = true
        APNotificationService.shared.setAppActive(true, joined: false)
        APNotificationService.shared.clearBackgroundDisconnectState()
    }

    func testDoesNotNotifyForIntentionalDisconnect() {
        APNotificationService.shared.setAppActive(false, joined: true)
        APNotificationService.shared.notifyDisconnectedDueToBackground(wasJoined: true, intentional: true)
        XCTAssertFalse(APNotificationService.shared.leftAppWhileJoined)
    }

    func testDoesNotNotifyWhenStillInForegroundWithoutBackgrounding() {
        APNotificationService.shared.setAppActive(true, joined: false)
        APNotificationService.shared.notifyDisconnectedDueToBackground(wasJoined: true, intentional: false)
        XCTAssertTrue(APNotificationService.shared.leftAppWhileJoined == false)
    }

    func testMarksBackgroundStateWhenLeavingAppWhileJoined() {
        APNotificationService.shared.setAppActive(false, joined: true)
        XCTAssertTrue(APNotificationService.shared.leftAppWhileJoined)
    }

    func testClearsBackgroundStateOnReconnect() {
        APNotificationService.shared.setAppActive(false, joined: true)
        APNotificationService.shared.clearBackgroundDisconnectState()
        XCTAssertFalse(APNotificationService.shared.leftAppWhileJoined)
    }
}
