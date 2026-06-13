import XCTest
@testable import ArchipelagoClient

@MainActor
final class ConnectionBookmarkStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var store: ConnectionBookmarkStore!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "ConnectionBookmarkStoreTests")!
        defaults.removePersistentDomain(forName: "ConnectionBookmarkStoreTests")
        store = ConnectionBookmarkStore(
            defaults: defaults,
            keychainService: "gg.archipelago.bookmarks.tests"
        )
    }

    override func tearDown() {
        for bookmark in store.bookmarks {
            store.delete(bookmark)
        }
        defaults.removePersistentDomain(forName: "ConnectionBookmarkStoreTests")
        super.tearDown()
    }

    func testAddAndReloadBookmark() {
        let bookmark = store.add(
            name: "Main MW",
            serverAddress: "archipelago.gg:38281",
            slotName: "Player1",
            password: nil
        )

        let reloaded = ConnectionBookmarkStore(
            defaults: defaults,
            keychainService: "gg.archipelago.bookmarks.tests"
        )
        XCTAssertEqual(reloaded.bookmarks.count, 1)
        XCTAssertEqual(reloaded.bookmarks.first?.id, bookmark.id)
        XCTAssertEqual(reloaded.bookmarks.first?.name, "Main MW")
        XCTAssertEqual(reloaded.bookmarks.first?.serverAddress, "archipelago.gg:38281")
        XCTAssertEqual(reloaded.bookmarks.first?.slotName, "Player1")
    }

    func testPasswordRoundTrip() {
        let bookmark = store.add(
            name: "Secure",
            serverAddress: "localhost:38281",
            slotName: "slot",
            password: "secret"
        )

        XCTAssertEqual(store.password(for: bookmark.id), "secret")

        let reloaded = ConnectionBookmarkStore(
            defaults: defaults,
            keychainService: "gg.archipelago.bookmarks.tests"
        )
        XCTAssertEqual(reloaded.password(for: bookmark.id), "secret")
    }

    func testUpdateBookmarkAndPassword() {
        let bookmark = store.add(
            name: "Old",
            serverAddress: "host:38281",
            slotName: "a",
            password: "old"
        )

        let updated = ConnectionBookmark(
            id: bookmark.id,
            name: "New",
            serverAddress: "new.host:38281",
            slotName: "b",
            createdAt: bookmark.createdAt
        )
        store.update(updated, password: "new")

        XCTAssertEqual(store.bookmarks.first?.name, "New")
        XCTAssertEqual(store.password(for: bookmark.id), "new")
    }

    func testDeleteRemovesBookmarkAndPassword() {
        let bookmark = store.add(
            name: "Temp",
            serverAddress: "host",
            slotName: "slot",
            password: "pw"
        )

        store.delete(bookmark)
        XCTAssertTrue(store.bookmarks.isEmpty)
        XCTAssertNil(store.password(for: bookmark.id))
    }

    func testBookmarkSubtitle() {
        let bookmark = ConnectionBookmark(
            name: "Test",
            serverAddress: "archipelago.gg",
            slotName: "roggle"
        )
        XCTAssertEqual(bookmark.subtitle, "roggle @ archipelago.gg")
    }
}
