import XCTest
@testable import ArchipelagoClient

@MainActor
final class ConnectionSessionManagerTests: XCTestCase {
    override func tearDown() {
        Persistence.saveConnectionSessions([])
        Persistence.activeConnectionSessionID = nil
        Persistence.primaryConnectionSessionID = nil
        super.tearDown()
    }

    func testMigratesLegacySessionWhenEmpty() {
        Persistence.lastServerAddress = "example.com:38281"
        Persistence.lastSlotName = "Player1"
        Persistence.saveConnectionSessions([])

        let manager = ConnectionSessionManager()

        XCTAssertEqual(manager.sessions.count, 1)
        XCTAssertEqual(manager.sessions[0].serverAddress, "example.com:38281")
        XCTAssertEqual(manager.sessions[0].slotName, "Player1")
        XCTAssertEqual(manager.activeContext.slotName, "Player1")
    }

    func testSwitchActiveSession() {
        let first = ConnectionSession(label: "A", serverAddress: "a.com", slotName: "A")
        let second = ConnectionSession(label: "B", serverAddress: "b.com", slotName: "B")
        Persistence.saveConnectionSessions([first, second])
        Persistence.activeConnectionSessionID = first.id
        Persistence.primaryConnectionSessionID = first.id

        let manager = ConnectionSessionManager()

        XCTAssertEqual(manager.sessions.count, 2)
        manager.setActiveSession(id: second.id)
        XCTAssertEqual(manager.activeContext.slotName, "B")
        XCTAssertNotEqual(manager.context(for: first.id)?.sessionID, manager.activeContext.sessionID)
    }

    func testApplyConnectedIdentityRenamesSessionLabel() {
        let session = ConnectionSession(label: "Slot 2", serverAddress: "host:38281", slotName: "PlayerB")
        Persistence.saveConnectionSessions([session])
        Persistence.activeConnectionSessionID = session.id

        let manager = ConnectionSessionManager()
        let context = manager.activeContext
        context.displayAddress = "host:38281"
        context.setSlotName("PlayerB")

        manager.applyConnectedIdentity(from: context)

        XCTAssertEqual(manager.sessions[0].label, "PlayerB")
    }

    func testRemoveSessionFallsBackToRemainingSession() {
        let first = ConnectionSession(label: "A")
        let second = ConnectionSession(label: "B")
        Persistence.saveConnectionSessions([first, second])
        Persistence.activeConnectionSessionID = second.id

        let manager = ConnectionSessionManager()
        manager.removeSession(id: second.id)

        XCTAssertEqual(manager.sessions.count, 1)
        XCTAssertEqual(manager.activeSessionID, first.id)
    }
}
