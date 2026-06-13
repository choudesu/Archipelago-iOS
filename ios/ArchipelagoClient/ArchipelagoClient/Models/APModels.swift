import Foundation

enum ClientStatus: Int, Codable, Sendable {
    case unknown = 0
    case connected = 5
    case ready = 10
    case playing = 20
    case goal = 30
}

enum HintStatus: Int, Codable, Sendable, CaseIterable {
    case unspecified = 0
    case noPriority = 10
    case avoid = 20
    case priority = 30
    case found = 40

    var displayName: String {
        switch self {
        case .found: return "(found)"
        case .unspecified: return "(unspecified)"
        case .noPriority: return "(no priority)"
        case .avoid: return "(avoid)"
        case .priority: return "(priority)"
        }
    }
}

enum SlotType: Int, Codable, Sendable {
    case spectator = 0
    case player = 1
    case group = 2
}

struct APVersion: Codable, Equatable, Sendable {
    var major: Int
    var minor: Int
    var build: Int

    static let clientVersion = APVersion(major: 0, minor: 6, build: 8)

    var simpleString: String { "\(major).\(minor).\(build)" }

    var tuple: [Int] { [major, minor, build] }
}

struct NetworkItem: Codable, Equatable, Sendable {
    var item: Int
    var location: Int
    var player: Int
    var flags: Int

    init(item: Int, location: Int, player: Int, flags: Int = 0) {
        self.item = item
        self.location = location
        self.player = player
        self.flags = flags
    }
}

struct NetworkPlayer: Codable, Equatable, Sendable {
    var team: Int
    var slot: Int
    var alias: String
    var name: String
}

struct NetworkSlot: Codable, Equatable, Sendable {
    var name: String
    var game: String
    var type: Int
    var groupMembers: [Int]

    enum CodingKeys: String, CodingKey {
        case name, game, type
        case groupMembers = "group_members"
    }

    init(name: String, game: String, type: Int, groupMembers: [Int] = []) {
        self.name = name
        self.game = game
        self.type = type
        self.groupMembers = groupMembers
    }

    /// APCodec decodes server payloads into typed values; fall back to raw dictionaries for tests.
    static func parseDecodedValue(_ value: Any) -> NetworkSlot? {
        if let slot = value as? NetworkSlot {
            return slot
        }
        guard let dict = value as? [String: Any],
              let json = try? JSONSerialization.data(withJSONObject: dict),
              let slot = try? JSONDecoder().decode(NetworkSlot.self, from: json) else {
            return nil
        }
        return slot
    }
}

struct HintEntry: Identifiable, Equatable, Sendable {
    var receivingPlayer: Int
    var findingPlayer: Int
    var location: Int
    var item: Int
    var found: Bool
    var entrance: String
    var itemFlags: Int
    var status: HintStatus

    var id: String {
        "\(findingPlayer)-\(location)-\(item)-\(receivingPlayer)-\(status.rawValue)"
    }

    init(from dict: [String: Any]) {
        receivingPlayer = dict["receiving_player"] as? Int ?? 0
        findingPlayer = dict["finding_player"] as? Int ?? 0
        location = dict["location"] as? Int ?? 0
        item = dict["item"] as? Int ?? 0
        found = dict["found"] as? Bool ?? false
        entrance = dict["entrance"] as? String ?? ""
        itemFlags = dict["item_flags"] as? Int ?? 0
        status = HintStatus(rawValue: dict["status"] as? Int ?? 0) ?? .unspecified
    }
}

struct JSONMessagePart: Codable, Equatable, Sendable {
    var text: String?
    var type: String?
    var color: String?
    var player: Int?
    var flags: Int?
    var hintStatus: Int?

    enum CodingKeys: String, CodingKey {
        case text, type, color, player, flags
        case hintStatus = "hint_status"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try Self.decodeFlexibleString(from: container, forKey: .text)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        color = try container.decodeIfPresent(String.self, forKey: .color)
        player = try Self.decodeFlexibleInt(from: container, forKey: .player)
        flags = try Self.decodeFlexibleInt(from: container, forKey: .flags)
        hintStatus = try Self.decodeFlexibleInt(from: container, forKey: .hintStatus)
    }

    private static func decodeFlexibleString(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> String? {
        if let value = try container.decodeIfPresent(String.self, forKey: key) {
            return value
        }
        if let value = try container.decodeIfPresent(Int.self, forKey: key) {
            return String(value)
        }
        return nil
    }

    private static func decodeFlexibleInt(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> Int? {
        if let value = try container.decodeIfPresent(Int.self, forKey: key) {
            return value
        }
        if let value = try container.decodeIfPresent(String.self, forKey: key) {
            return Int(value)
        }
        return nil
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(text, forKey: .text)
        try container.encodeIfPresent(type, forKey: .type)
        try container.encodeIfPresent(color, forKey: .color)
        try container.encodeIfPresent(player, forKey: .player)
        try container.encodeIfPresent(flags, forKey: .flags)
        try container.encodeIfPresent(hintStatus, forKey: .hintStatus)
    }
}

struct ChatLogEntry: Identifiable, Equatable, Sendable {
    let id = UUID()
    let text: String
    let attributedParts: [JSONMessagePart]
    let isCommandEcho: Bool
    let timestamp: Date

    init(text: String, parts: [JSONMessagePart] = [], isCommandEcho: Bool = false) {
        self.text = text
        self.attributedParts = parts
        self.isCommandEcho = isCommandEcho
        self.timestamp = Date()
    }
}

struct GamesPackage: Codable, Sendable {
    var itemNameToID: [String: Int]
    var locationNameToID: [String: Int]
    var itemNameGroups: [String: [String]]?
    var locationNameGroups: [String: [String]]?
    var checksum: String?

    enum CodingKeys: String, CodingKey {
        case itemNameToID = "item_name_to_id"
        case locationNameToID = "location_name_to_id"
        case itemNameGroups = "item_name_groups"
        case locationNameGroups = "location_name_groups"
        case checksum
    }

    static func parse(gameData: [String: Any]) -> GamesPackage? {
        guard let itemRaw = gameData["item_name_to_id"] as? [String: Any],
              let locationRaw = gameData["location_name_to_id"] as? [String: Any] else {
            return nil
        }

        return GamesPackage(
            itemNameToID: parseNameToID(itemRaw),
            locationNameToID: parseNameToID(locationRaw),
            itemNameGroups: parseNameGroups(gameData["item_name_groups"]),
            locationNameGroups: parseNameGroups(gameData["location_name_groups"]),
            checksum: gameData["checksum"] as? String
        )
    }

    private static func parseNameToID(_ raw: [String: Any]) -> [String: Int] {
        var result: [String: Int] = [:]
        for (name, value) in raw {
            if let id = coerceInt(value) {
                result[name] = id
            }
        }
        return result
    }

    private static func parseNameGroups(_ value: Any?) -> [String: [String]]? {
        guard let raw = value as? [String: Any] else { return nil }
        var result: [String: [String]] = [:]
        for (name, groupValue) in raw {
            if let names = groupValue as? [String] {
                result[name] = names
            }
        }
        return result.isEmpty ? nil : result
    }

    private static func coerceInt(_ value: Any) -> Int? {
        switch value {
        case let int as Int:
            return int
        case let int64 as Int64:
            return Int(int64)
        case let number as NSNumber:
            return Int(truncating: number)
        case let double as Double:
            return Int(double)
        case let string as String:
            return Int(string)
        default:
            return nil
        }
    }
}

struct DataPackage: Codable, Sendable {
    var games: [String: GamesPackage]
}

struct DataPackageStatusInfo: Equatable, Identifiable, Sendable {
    enum Phase: Equatable, Sendable {
        case loading
        case loaded
        case failed
    }

    let id: UUID
    var phase: Phase
    var games: [String]

    init(phase: Phase, games: [String], id: UUID = UUID()) {
        self.id = id
        self.phase = phase
        self.games = games
    }

    var prefix: String {
        switch phase {
        case .loading: "Loading data packages"
        case .loaded: "Loaded data packages"
        case .failed: "Failed to load data packages"
        }
    }
}

enum ConnectionState: Equatable, Sendable {
    case disconnected
    case connecting
    case connected
    case authenticating
}

struct ParsedServerURL: Equatable, Sendable {
    var websocketURL: URL
    var username: String?
    var password: String?
    var displayAddress: String
}
