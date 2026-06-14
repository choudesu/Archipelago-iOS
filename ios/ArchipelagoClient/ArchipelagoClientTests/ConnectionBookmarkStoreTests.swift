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

    func testExportIncludesPasswords() throws {
        let bookmark = store.add(
            name: "Secure",
            serverAddress: "archipelago.gg:38281",
            slotName: "slot",
            password: "secret"
        )

        let data = try store.exportData()
        let items = try ConnectionBookmarkTransfer.decode(data)

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.name, "Secure")
        XCTAssertEqual(items.first?.serverAddress, "archipelago.gg:38281")
        XCTAssertEqual(items.first?.slotName, "slot")
        XCTAssertEqual(items.first?.password, "secret")
        XCTAssertEqual(items.first?.createdAt, bookmark.createdAt)
    }

    func testExportWithoutPasswords() throws {
        _ = store.add(
            name: "Secure",
            serverAddress: "archipelago.gg:38281",
            slotName: "slot",
            password: "secret"
        )

        let data = try store.exportData(includePasswords: false)
        let items = try ConnectionBookmarkTransfer.decode(data)

        XCTAssertEqual(items.count, 1)
        XCTAssertNil(items.first?.password)
    }

    func testImportMergeAddsToExisting() throws {
        _ = store.add(
            name: "Existing",
            serverAddress: "host:38281",
            slotName: "a",
            password: nil
        )
        let importData = try ConnectionBookmarkTransfer.encode(
            [
                ConnectionBookmark(name: "Imported", serverAddress: "new.host:38281", slotName: "b")
            ],
            passwords: [:]
        )

        let count = try store.importBookmarks(from: importData, mode: .merge)

        XCTAssertEqual(count, 1)
        XCTAssertEqual(store.bookmarks.count, 2)
        XCTAssertEqual(store.bookmarks.last?.name, "Imported")
        XCTAssertEqual(store.bookmarks.last?.serverAddress, "new.host:38281")
    }

    func testImportReplaceRemovesExisting() throws {
        let existing = store.add(
            name: "Existing",
            serverAddress: "host:38281",
            slotName: "a",
            password: "old"
        )
        let replacement = ConnectionBookmark(
            name: "Replacement",
            serverAddress: "new.host:38281",
            slotName: "b"
        )
        let importData = try ConnectionBookmarkTransfer.encode(
            [replacement],
            passwords: [replacement.id: "new"]
        )

        let count = try store.importBookmarks(from: importData, mode: .replace)

        XCTAssertEqual(count, 1)
        XCTAssertEqual(store.bookmarks.count, 1)
        XCTAssertEqual(store.bookmarks.first?.name, "Replacement")
        XCTAssertNil(store.password(for: existing.id))
        XCTAssertEqual(store.password(for: store.bookmarks.first!.id), "new")
    }

    func testImportRoundTripRestoresPassword() throws {
        _ = store.add(
            name: "Round Trip",
            serverAddress: "archipelago.gg:38281",
            slotName: "slot",
            password: "pw"
        )
        let exportData = try store.exportData()

        for bookmark in store.bookmarks {
            store.delete(bookmark)
        }
        XCTAssertTrue(store.bookmarks.isEmpty)

        let count = try store.importBookmarks(from: exportData, mode: .merge)

        XCTAssertEqual(count, 1)
        XCTAssertEqual(store.bookmarks.first?.name, "Round Trip")
        XCTAssertEqual(store.password(for: store.bookmarks.first!.id), "pw")
    }

    func testImportEmptyThrows() throws {
        let importData = try ConnectionBookmarkTransfer.encode([], passwords: [:])

        XCTAssertThrowsError(try store.importBookmarks(from: importData, mode: .merge)) { error in
            XCTAssertEqual(error as? ConnectionBookmarkTransferError, .empty)
        }
    }

    func testDecodeLegacyBookmarkArray() throws {
        let legacy = [
            ConnectionBookmark(name: "Legacy", serverAddress: "host:38281", slotName: "slot")
        ]
        let data = try JSONEncoder().encode(legacy)
        let items = try ConnectionBookmarkTransfer.decode(data)

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.name, "Legacy")
        XCTAssertEqual(items.first?.serverAddress, "host:38281")
        XCTAssertNil(items.first?.password)
    }
}
