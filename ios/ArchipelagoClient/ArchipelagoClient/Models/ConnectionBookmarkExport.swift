import Foundation

struct ConnectionBookmarksFile: Codable, Equatable, Sendable {
    static let currentVersion = 1

    var version: Int
    var bookmarks: [ExportedConnectionBookmark]

    init(version: Int = Self.currentVersion, bookmarks: [ExportedConnectionBookmark]) {
        self.version = version
        self.bookmarks = bookmarks
    }
}

struct ExportedConnectionBookmark: Codable, Equatable, Sendable {
    var name: String
    var serverAddress: String
    var slotName: String
    var password: String?
    var createdAt: Date?

    init(
        name: String,
        serverAddress: String,
        slotName: String,
        password: String? = nil,
        createdAt: Date? = nil
    ) {
        self.name = name
        self.serverAddress = serverAddress
        self.slotName = slotName
        self.password = password
        self.createdAt = createdAt
    }

    init(bookmark: ConnectionBookmark, password: String?) {
        self.init(
            name: bookmark.name,
            serverAddress: bookmark.serverAddress,
            slotName: bookmark.slotName,
            password: password,
            createdAt: bookmark.createdAt
        )
    }
}

enum ConnectionBookmarkImportMode {
    case merge
    case replace
}

enum ConnectionBookmarkTransferError: LocalizedError, Equatable {
    case invalidFormat
    case empty
    case nothingToExport

    var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return "The file is not a valid Archipelago bookmarks export."
        case .empty:
            return "The file does not contain any bookmarks."
        case .nothingToExport:
            return "There are no bookmarks to export."
        }
    }
}

enum ConnectionBookmarkTransfer {
    static func encode(_ bookmarks: [ConnectionBookmark], passwords: [UUID: String]) throws -> Data {
        let items = bookmarks.map { bookmark in
            ExportedConnectionBookmark(
                bookmark: bookmark,
                password: passwords[bookmark.id]
            )
        }
        let file = ConnectionBookmarksFile(bookmarks: items)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(file)
    }

    static func decode(_ data: Data) throws -> [ExportedConnectionBookmark] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if let file = try? decoder.decode(ConnectionBookmarksFile.self, from: data) {
            return file.bookmarks
        }
        if let items = try? decoder.decode([ExportedConnectionBookmark].self, from: data) {
            return items
        }
        if let legacy = try? decoder.decode([ConnectionBookmark].self, from: data) {
            return legacy.map {
                ExportedConnectionBookmark(
                    name: $0.name,
                    serverAddress: $0.serverAddress,
                    slotName: $0.slotName,
                    createdAt: $0.createdAt
                )
            }
        }
        throw ConnectionBookmarkTransferError.invalidFormat
    }
}
