import Foundation
import CryptoKit

enum DataPackageChecksum {
    static func checksum(for package: GamesPackage) -> String {
        var copy = package
        copy.checksum = nil
        guard let encoded = try? APCodec.encode([orderedPackageDict(copy)]) else {
            return ""
        }
        let digest = Insecure.SHA1.hash(data: Data(encoded.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func orderedPackageDict(_ package: GamesPackage) -> [String: Any] {
        var dict: [String: Any] = [:]
        dict["item_name_to_id"] = sortedNameToID(package.itemNameToID)
        dict["location_name_to_id"] = sortedNameToID(package.locationNameToID)
        if let groups = package.itemNameGroups {
            dict["item_name_groups"] = sortedGroups(groups)
        }
        if let groups = package.locationNameGroups {
            dict["location_name_groups"] = sortedGroups(groups)
        }
        return dict
    }

    private static func sortedNameToID(_ map: [String: Int]) -> [String: Int] {
        var ordered: [String: Int] = [:]
        for key in map.keys.sorted() {
            ordered[key] = map[key]
        }
        return ordered
    }

    private static func sortedGroups(_ groups: [String: [String]]) -> [String: [String]] {
        var ordered: [String: [String]] = [:]
        for key in groups.keys.sorted() {
            ordered[key] = groups[key]
        }
        return ordered
    }
}

final class DataPackageCache {
    static let shared = DataPackageCache()

    private let fileManager = FileManager.default
    private var memory: [String: GamesPackage] = [:]

    private init() {
        loadBundledArchipelagoPackage()
    }

    private var cacheDirectory: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("DataPackages", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func loadBundledArchipelagoPackage() {
        guard let url = Bundle.main.url(forResource: "archipelago_datapackage", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let package = try? JSONDecoder().decode(GamesPackage.self, from: data) else {
            let fallback = GamesPackage(
                itemNameToID: ["Nothing": -1],
                locationNameToID: ["Cheat Console": -1, "Server": -2],
                itemNameGroups: nil,
                locationNameGroups: nil,
                checksum: nil
            )
            var mutable = fallback
            mutable.checksum = DataPackageChecksum.checksum(for: mutable)
            memory["Archipelago"] = mutable
            return
        }
        var mutable = package
        mutable.checksum = DataPackageChecksum.checksum(for: mutable)
        memory["Archipelago"] = mutable
    }

    func package(for game: String) -> GamesPackage? {
        memory[game]
    }

    func checksum(for game: String) -> String? {
        memory[game]?.checksum
    }

    func store(package: GamesPackage, game: String) {
        var mutable = package
        mutable.checksum = DataPackageChecksum.checksum(for: mutable)
        memory[game] = mutable
        let url = cacheDirectory.appendingPathComponent("\(game)_\(mutable.checksum ?? "unknown").json")
        if let data = try? JSONEncoder().encode(mutable) {
            try? data.write(to: url)
        }
    }

    func loadFromDisk(game: String, checksum: String) -> GamesPackage? {
        let url = cacheDirectory.appendingPathComponent("\(game)_\(checksum).json")
        guard let data = try? Data(contentsOf: url),
              var package = try? JSONDecoder().decode(GamesPackage.self, from: data) else {
            return nil
        }
        package.checksum = checksum
        memory[game] = package
        return package
    }

    func gamesNeedingUpdate(relevantGames: Set<String>, remoteChecksums: [String: String]) -> Set<String> {
        var needed: Set<String> = []
        var games = relevantGames
        games.insert("Archipelago")

        for game in games {
            guard let remote = remoteChecksums[game], !remote.isEmpty else {
                needed.insert(game)
                continue
            }
            if checksum(for: game) == remote {
                continue
            }
            if let cached = loadFromDisk(game: game, checksum: remote) {
                memory[game] = cached
                continue
            }
            needed.insert(game)
        }
        return needed
    }
}
