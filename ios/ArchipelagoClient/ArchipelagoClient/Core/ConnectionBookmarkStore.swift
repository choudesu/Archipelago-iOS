import Foundation
import Security

@MainActor
final class ConnectionBookmarkStore: ObservableObject {
    static let shared = ConnectionBookmarkStore()

    @Published private(set) var bookmarks: [ConnectionBookmark] = []

    private let defaults: UserDefaults
    private let keychainService: String
    private static let storageKey = "ap.client.connectionBookmarks"

    init(defaults: UserDefaults = .standard, keychainService: String = "gg.archipelago.bookmarks") {
        self.defaults = defaults
        self.keychainService = keychainService
        load()
    }

    func add(
        name: String,
        serverAddress: String,
        slotName: String,
        password: String?
    ) -> ConnectionBookmark {
        let bookmark = ConnectionBookmark(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            serverAddress: serverAddress.trimmingCharacters(in: .whitespacesAndNewlines),
            slotName: slotName.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        bookmarks.append(bookmark)
        persistPassword(password, for: bookmark.id)
        save()
        return bookmark
    }

    func update(_ bookmark: ConnectionBookmark, password: String?) {
        guard let index = bookmarks.firstIndex(where: { $0.id == bookmark.id }) else { return }
        bookmarks[index] = bookmark
        if let password {
            if password.isEmpty {
                deletePassword(for: bookmark.id)
            } else {
                persistPassword(password, for: bookmark.id)
            }
        }
        save()
    }

    func delete(_ bookmark: ConnectionBookmark) {
        bookmarks.removeAll { $0.id == bookmark.id }
        deletePassword(for: bookmark.id)
        save()
    }

    func move(fromOffsets: IndexSet, toOffset: Int) {
        bookmarks.move(fromOffsets: fromOffsets, toOffset: toOffset)
        save()
    }

    func password(for id: UUID) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: id.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let password = String(data: data, encoding: .utf8) else {
            return nil
        }
        return password
    }

    private func load() {
        guard let data = defaults.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([ConnectionBookmark].self, from: data) else {
            bookmarks = []
            return
        }
        bookmarks = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(bookmarks) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    private func persistPassword(_ password: String?, for id: UUID) {
        deletePassword(for: id)
        guard let password, !password.isEmpty else { return }
        guard let data = password.data(using: .utf8) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: id.uuidString,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    private func deletePassword(for id: UUID) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: id.uuidString
        ]
        SecItemDelete(query as CFDictionary)
    }
}
