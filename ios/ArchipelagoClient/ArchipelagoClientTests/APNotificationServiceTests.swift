import XCTest
@testable import ArchipelagoClient

@MainActor
final class APNotificationServiceTests: XCTestCase {
    override func setUp() {
        super.setUp()
        Persistence.notificationsEnabled = true
        APNotificationService.shared.clearBackgroundDisconnectState()
    }

    func testDoesNotScheduleWithoutNotificationsEnabled() {
        Persistence.notificationsEnabled = false
        APNotificationService.shared.handleEnterBackground(joined: true, connected: true)
        XCTAssertFalse(APNotificationService.shared.leftAppWhileJoined)
    }

    func testMarksBackgroundWhenJoinedAndConnected() {
        APNotificationService.shared.handleEnterBackground(joined: true, connected: true)
        XCTAssertTrue(APNotificationService.shared.leftAppWhileJoined)
    }

    func testDoesNotMarkBackgroundWhenNotConnected() {
        APNotificationService.shared.handleEnterBackground(joined: true, connected: false)
        XCTAssertFalse(APNotificationService.shared.leftAppWhileJoined)
    }

    func testForegroundWhileConnectedClearsBackgroundState() {
        APNotificationService.shared.handleEnterBackground(joined: true, connected: true)
        APNotificationService.shared.handleEnterForeground(stillConnected: true)
        XCTAssertFalse(APNotificationService.shared.leftAppWhileJoined)
    }

    func testDoesNotNotifyForIntentionalDisconnect() {
        APNotificationService.shared.handleEnterBackground(joined: true, connected: true)
        APNotificationService.shared.notifyDisconnectedDueToBackground(wasJoined: true, intentional: true)
        XCTAssertTrue(APNotificationService.shared.leftAppWhileJoined)
    }

    func testClearsBackgroundStateOnDemand() {
        APNotificationService.shared.handleEnterBackground(joined: true, connected: true)
        APNotificationService.shared.clearBackgroundDisconnectState()
        XCTAssertFalse(APNotificationService.shared.leftAppWhileJoined)
    }
}
