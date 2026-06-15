import Foundation

final class NameLookup {
    private var itemStores: [String: [Int: String]] = [:]
    private var locationStores: [String: [Int: String]] = [:]
    private var archipelagoItems: [Int: String] = [:]
    private var archipelagoLocations: [Int: String] = [:]

    init() {
        if let package = DataPackageCache.shared.package(for: "Archipelago") {
            updateGame(package, game: "Archipelago")
        }
    }

    func updateGame(_ package: GamesPackage, game: String) {
        var itemMap: [Int: String] = archipelagoItems
        for (name, id) in package.itemNameToID {
            itemMap[id] = name
        }
        var locationMap: [Int: String] = archipelagoLocations
        for (name, id) in package.locationNameToID {
            locationMap[id] = name
        }
        itemStores[game] = itemMap
        locationStores[game] = locationMap

        if game == "Archipelago" {
            archipelagoItems = itemMap
            archipelagoLocations = locationMap
        }
    }

    func itemName(_ id: Int, game: String?) -> String {
        let lookupGame = game ?? "Archipelago"
        if let name = itemStores[lookupGame]?[id] {
            return name
        }
        return "Unknown item (ID: \(id))"
    }

    func locationName(_ id: Int, game: String?) -> String {
        let lookupGame = game ?? "Archipelago"
        if let name = locationStores[lookupGame]?[id] {
            return name
        }
        return "Unknown location (ID: \(id))"
    }

    func lookupItemInSlot(_ id: Int, slot: Int?, slotInfo: [Int: NetworkSlot]) -> String {
        let game = slot.flatMap { slotInfo[$0]?.game }
        return itemName(id, game: game)
    }

    func lookupLocationInSlot(_ id: Int, slot: Int?, slotInfo: [Int: NetworkSlot]) -> String {
        let game = slot.flatMap { slotInfo[$0]?.game }
        return locationName(id, game: game)
    }

    func itemNames(for game: String) -> [String] {
        guard let store = itemStores[game] else { return [] }
        return store.values.sorted()
    }

    func locationNames(for game: String) -> [String] {
        guard let store = locationStores[game] else { return [] }
        return store.values.sorted()
    }

    func allItemNames(for game: String) -> [(id: Int, name: String)] {
        guard let store = itemStores[game] else { return [] }
        return store.map { ($0.key, $0.value) }.sorted { $0.name < $1.name }
    }

    func allLocationEntries(for game: String) -> [(id: Int, name: String)] {
        guard let store = locationStores[game] else { return [] }
        return store.map { ($0.key, $0.value) }.sorted { $0.name < $1.name }
    }
}
