import Foundation

enum PopTrackerPackError: LocalizedError {
    case missingManifest
    case invalidJSON(String)
    case unsupportedVariant(String)
    case missingAPVariant
    case incompatibleVersion(String)
    case installFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingManifest: return "Pack is missing manifest.json."
        case .invalidJSON(let detail): return "Invalid pack JSON: \(detail)"
        case .unsupportedVariant(let uid): return "Variant \"\(uid)\" is not available in this pack."
        case .missingAPVariant: return "Pack has no variant with Archipelago (\"ap\") support."
        case .incompatibleVersion(let detail): return detail
        case .installFailed(let detail): return "Could not install pack: \(detail)"
        }
    }
}

struct PopTrackerManifest: Codable, Equatable {
    struct Variant: Codable, Equatable {
        let displayName: String
        let flags: [String]

        enum CodingKeys: String, CodingKey {
            case displayName = "display_name"
            case flags
        }

        var supportsArchipelago: Bool { flags.contains("ap") }
        var supportsManualChecks: Bool { flags.contains("apmanual") }
        var supportsHintGame: Bool { flags.contains("aphintgame") }
    }

    let name: String
    let gameName: String
    let packageUID: String
    let packageVersion: String
    let minPoptrackerVersion: String?
    let variants: [String: Variant]

    enum CodingKeys: String, CodingKey {
        case name
        case gameName = "game_name"
        case packageUID = "package_uid"
        case packageVersion = "package_version"
        case minPoptrackerVersion = "min_poptracker_version"
        case variants
    }
}

enum PopTrackerVariantResolver {
    static func resolveVariant(
        requested: String?,
        packUID: String,
        persistedPackUID: String?,
        persistedVariantUID: String?,
        manifest: PopTrackerManifest
    ) throws -> String {
        if let requested {
            guard manifest.variants[requested] != nil else {
                throw PopTrackerPackError.unsupportedVariant(requested)
            }
            return requested
        }
        if persistedPackUID == packUID,
           let persistedVariantUID,
           manifest.variants[persistedVariantUID] != nil {
            return persistedVariantUID
        }
        if let apVariant = manifest.variants.first(where: { $0.value.supportsArchipelago }) {
            return apVariant.key
        }
        return manifest.variants.keys.sorted().first ?? "standard"
    }
}

struct PopTrackerPackItem: Codable, Identifiable, Equatable {
    struct Stage: Codable, Equatable {
        let img: String?
        let codes: String?
        let inheritCodes: Bool?

        enum CodingKeys: String, CodingKey {
            case img
            case codes
            case inheritCodes = "inherit_codes"
        }
    }

    let name: String
    let type: String
    let img: String?
    let codes: String?
    let stages: [Stage]?
    let maxQuantity: Int?

    var id: String { codes ?? name }

    enum CodingKeys: String, CodingKey {
        case name
        case type
        case img
        case codes
        case stages
        case maxQuantity = "max_quantity"
    }

    var itemCodes: [String] {
        var result: [String] = []
        if let codes, !codes.isEmpty {
            result.append(codes)
        }
        for stage in stages ?? [] {
            if let code = stage.codes, !code.isEmpty {
                result.append(code)
            }
        }
        return result
    }
}

struct PopTrackerMapLocation: Codable, Equatable {
    let map: String
    let x: Double
    let y: Double
}

struct PopTrackerLocationSection: Codable, Equatable, Identifiable {
    let name: String
    let itemCount: Int?

    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name
        case itemCount = "item_count"
    }
}

struct PopTrackerLocationNode: Codable, Equatable, Identifiable {
    let name: String
    let children: [PopTrackerLocationNode]?
    let sections: [PopTrackerLocationSection]?
    let mapLocations: [PopTrackerMapLocation]?

    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name
        case children
        case sections
        case mapLocations = "map_locations"
    }
}

struct PopTrackerMapDefinition: Codable, Identifiable, Equatable {
    let name: String
    let img: String
    let locationSize: Double?

    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name
        case img
        case locationSize = "location_size"
    }
}

struct PopTrackerInstalledPack: Codable, Equatable, Identifiable {
    let packageUID: String
    let name: String
    let gameName: String
    let packageVersion: String
    let installedAt: Date
    let variants: [String]

    var id: String { packageUID }
}

struct PopTrackerLoadedPack: Equatable {
    let install: PopTrackerInstalledPack
    let rootURL: URL
    let manifest: PopTrackerManifest
    let variantUID: String
    let items: [PopTrackerPackItem]
    let locations: [PopTrackerLocationNode]
    let maps: [PopTrackerMapDefinition]
    let itemMapping: [Int: [String]]
    let locationMapping: [Int: [String]]
    let sectionPaths: [String]
    let sectionPathByAPLocationID: [Int: [String]]

    var gameName: String { manifest.gameName.trimmingCharacters(in: .whitespacesAndNewlines) }
    var supportsManualChecks: Bool { manifest.variants[variantUID]?.supportsManualChecks == true }

    func assetURL(for relativePath: String) -> URL {
        rootURL.appendingPathComponent(relativePath)
    }

    func apLocationID(forSectionPath path: String) -> Int? {
        for (locationID, paths) in sectionPathByAPLocationID where paths.contains(path) {
            return locationID
        }
        return nil
    }
}

struct PopTrackerSectionMarker: Identifiable, Equatable {
    let id: String
    let locationName: String
    let mapName: String
    let x: Double
    let y: Double
    let checked: Bool
    let apLocationID: Int?
}
