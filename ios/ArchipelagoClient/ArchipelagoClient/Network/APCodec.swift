import Foundation

enum APCodecError: Error, LocalizedError {
    case invalidJSON
    case unsupportedType(String)

    var errorDescription: String? {
        switch self {
        case .invalidJSON: return "Invalid JSON from server"
        case .unsupportedType(let type): return "Unsupported encoded type: \(type)"
        }
    }
}

enum APCodec {
    private static let allowlist: [String: (Dictionary<String, Any>) -> Any] = [
        "NetworkItem": { dict in
            NetworkItem(
                item: dict["item"] as? Int ?? 0,
                location: dict["location"] as? Int ?? 0,
                player: dict["player"] as? Int ?? 0,
                flags: dict["flags"] as? Int ?? 0
            )
        },
        "NetworkPlayer": { dict in
            NetworkPlayer(
                team: dict["team"] as? Int ?? 0,
                slot: dict["slot"] as? Int ?? 0,
                alias: dict["alias"] as? String ?? "",
                name: dict["name"] as? String ?? ""
            )
        },
        "NetworkSlot": { dict in
            NetworkSlot(
                name: dict["name"] as? String ?? "",
                game: dict["game"] as? String ?? "",
                type: dict["type"] as? Int ?? 0,
                groupMembers: dict["group_members"] as? [Int] ?? []
            )
        }
    ]

    static func encode(_ messages: [Any]) throws -> String {
        let converted = messages.map { convertForEncoding($0) }
        let data = try JSONSerialization.data(withJSONObject: converted, options: [.sortedKeys])
        guard let string = String(data: data, encoding: .utf8) else {
            throw APCodecError.invalidJSON
        }
        return string
    }

    static func decode(_ text: String) throws -> [[String: Any]] {
        guard let data = text.data(using: .utf8),
              let raw = try JSONSerialization.jsonObject(with: data) as? [Any] else {
            throw APCodecError.invalidJSON
        }
        return raw.compactMap { value in
            guard let dict = value as? [String: Any] else { return nil }
            return convertFromDecoding(dict) as? [String: Any]
        }
    }

    private static func convertForEncoding(_ value: Any) -> Any {
        let mirror = Mirror(reflecting: value)
        if mirror.displayStyle == .optional {
            if let child = mirror.children.first {
                return convertForEncoding(child.value)
            }
            return NSNull()
        }

        switch value { {
        case let item as NetworkItem:
            return taggedDict([
                "class": "NetworkItem",
                "item": item.item,
                "location": item.location,
                "player": item.player,
                "flags": item.flags
            ])
        case let player as NetworkPlayer:
            return taggedDict([
                "class": "NetworkPlayer",
                "team": player.team,
                "slot": player.slot,
                "alias": player.alias,
                "name": player.name
            ])
        case let slot as NetworkSlot:
            return taggedDict([
                "class": "NetworkSlot",
                "name": slot.name,
                "game": slot.game,
                "type": slot.type,
                "group_members": slot.groupMembers
            ])
        case let version as APVersion:
            return taggedDict([
                "class": "Version",
                "major": version.major,
                "minor": version.minor,
                "build": version.build
            ])
        case let dict as [String: Any]:
            return dict.mapValues { convertForEncoding($0) }
        case let array as [Any]:
            return array.map { convertForEncoding($0) }
        case let set as Set<Int>:
            return Array(set).sorted()
        case let set as Set<String>:
            return Array(set).sorted()
        default:
            return value
        }
    }

    private static func convertFromDecoding(_ value: Any) -> Any {
        switch value {
        case let dict as [String: Any]:
            if let className = dict["class"] as? String {
                if className == "Version" {
                    return APVersion(
                        major: dict["major"] as? Int ?? dict["Major"] as? Int ?? 0,
                        minor: dict["minor"] as? Int ?? dict["Minor"] as? Int ?? 0,
                        build: dict["build"] as? Int ?? dict["Build"] as? Int ?? 0
                    )
                }
                if let factory = allowlist[className] {
                    return factory(dict)
                }
            }
            var converted: [String: Any] = [:]
            for (key, val) in dict {
                converted[key] = convertFromDecoding(val)
            }
            return converted
        case let array as [Any]:
            return array.map { convertFromDecoding($0) }
        default:
            return value
        }
    }

    private static func taggedDict(_ dict: [String: Any]) -> [String: Any] {
        dict
    }

    static func parseVersion(_ value: Any) -> APVersion {
        if let version = value as? APVersion {
            return version
        }
        if let dict = value as? [String: Any] {
            return APVersion(
                major: dict["major"] as? Int ?? dict["Major"] as? Int ?? 0,
                minor: dict["minor"] as? Int ?? dict["Minor"] as? Int ?? 0,
                build: dict["build"] as? Int ?? dict["Build"] as? Int ?? 0
            )
        }
        if let tuple = value as? [Int], tuple.count >= 3 {
            return APVersion(major: tuple[0], minor: tuple[1], build: tuple[2])
        }
        return APVersion(major: 0, minor: 0, build: 0)
    }
}
