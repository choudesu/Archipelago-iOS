import Foundation

enum PopTrackerPackLoader {
    static func loadInstalledPack(
        install: PopTrackerInstalledPack,
        rootURL: URL,
        variantUID: String
    ) throws -> PopTrackerLoadedPack {
        let manifestURL = rootURL.appendingPathComponent("manifest.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw PopTrackerPackError.missingManifest
        }
        let manifestText = try String(contentsOf: manifestURL, encoding: .utf8)
        let manifest = try JSONC.decode(PopTrackerManifest.self, from: manifestText)
        guard let variant = manifest.variants[variantUID] else {
            throw PopTrackerPackError.unsupportedVariant(variantUID)
        }
        guard variant.supportsArchipelago else {
            throw PopTrackerPackError.missingAPVariant
        }

        let variantRoot = rootURL.appendingPathComponent(variantUID)
        let searchRoots = FileManager.default.fileExists(atPath: variantRoot.path)
            ? [variantRoot, rootURL]
            : [rootURL]

        let items = try loadItems(from: searchRoots)
        let locations = try loadLocations(from: searchRoots)
        let maps = try loadMaps(from: searchRoots)
        let itemMapping = PopTrackerMappingLoader.loadItemMapping(from: rootURL)
        let locationMapping = PopTrackerMappingLoader.loadLocationMapping(from: rootURL)
        let sectionPaths = buildSectionPaths(locations)
        let sectionPathByAPLocationID = invertLocationMapping(locationMapping)

        return PopTrackerLoadedPack(
            install: install,
            rootURL: rootURL,
            manifest: manifest,
            variantUID: variantUID,
            items: items,
            locations: locations,
            maps: maps,
            itemMapping: itemMapping,
            locationMapping: locationMapping,
            sectionPaths: sectionPaths,
            sectionPathByAPLocationID: sectionPathByAPLocationID
        )
    }

    private static func loadItems(from roots: [URL]) throws -> [PopTrackerPackItem] {
        for root in roots {
            let directory = root.appendingPathComponent("items")
            if let urls = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
                let jsonFiles = urls.filter {
                    let ext = $0.pathExtension.lowercased()
                    return ext == "json" || ext == "jsonc"
                }.sorted { $0.lastPathComponent < $1.lastPathComponent }
                if !jsonFiles.isEmpty {
                    var items: [PopTrackerPackItem] = []
                    for url in jsonFiles {
                        items.append(contentsOf: try JSONC.decode([PopTrackerPackItem].self, from: url))
                    }
                    return items
                }
            }
            for name in ["items/items.json", "items/items.jsonc"] {
                let url = root.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: url.path) {
                    return try JSONC.decode([PopTrackerPackItem].self, from: url)
                }
            }
        }
        return []
    }

    private static func loadLocations(from roots: [URL]) throws -> [PopTrackerLocationNode] {
        for root in roots {
            let directory = root.appendingPathComponent("locations")
            if let urls = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
                let jsonFiles = urls.filter {
                    let ext = $0.pathExtension.lowercased()
                    return ext == "json" || ext == "jsonc"
                }.sorted { $0.lastPathComponent < $1.lastPathComponent }
                if !jsonFiles.isEmpty {
                    var nodes: [PopTrackerLocationNode] = []
                    for url in jsonFiles {
                        nodes.append(contentsOf: try JSONC.decode([PopTrackerLocationNode].self, from: url))
                    }
                    return nodes
                }
            }
            for name in ["locations/locations.json", "locations/locations.jsonc"] {
                let url = root.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: url.path) {
                    return try JSONC.decode([PopTrackerLocationNode].self, from: url)
                }
            }
        }
        return []
    }

    private static func loadMaps(from roots: [URL]) throws -> [PopTrackerMapDefinition] {
        for root in roots {
            let directory = root.appendingPathComponent("maps")
            if let urls = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
                let jsonFiles = urls.filter {
                    let ext = $0.pathExtension.lowercased()
                    return ext == "json" || ext == "jsonc"
                }.sorted { $0.lastPathComponent < $1.lastPathComponent }
                if !jsonFiles.isEmpty {
                    var maps: [PopTrackerMapDefinition] = []
                    var seenNames = Set<String>()
                    for url in jsonFiles {
                        for map in try JSONC.decode([PopTrackerMapDefinition].self, from: url) {
                            if seenNames.insert(map.name).inserted {
                                maps.append(map)
                            }
                        }
                    }
                    return maps
                }
            }
            for name in ["maps/maps.json", "maps/maps.jsonc"] {
                let url = root.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: url.path) {
                    return try JSONC.decode([PopTrackerMapDefinition].self, from: url)
                }
            }
        }
        return []
    }

    static func referencedMapNames(from nodes: [PopTrackerLocationNode]) -> Set<String> {
        var names = Set<String>()
        collectReferencedMapNames(nodes: nodes, into: &names)
        return names
    }

    private static func collectReferencedMapNames(
        nodes: [PopTrackerLocationNode],
        into names: inout Set<String>
    ) {
        for node in nodes {
            for mapLocation in node.mapLocations ?? [] {
                names.insert(mapLocation.map)
            }
            if let children = node.children {
                collectReferencedMapNames(nodes: children, into: &names)
            }
        }
    }

    static func buildSectionPaths(_ nodes: [PopTrackerLocationNode], parentPath: String = "") -> [String] {
        var paths: [String] = []
        for node in nodes {
            let nodePath = parentPath.isEmpty ? node.name : "\(parentPath)/\(node.name)"
            if let sections = node.sections {
                for section in sections {
                    paths.append("\(nodePath)/\(section.name)")
                }
            }
            if let children = node.children {
                paths.append(contentsOf: buildSectionPaths(children, parentPath: nodePath))
            }
        }
        return paths
    }

    static func invertLocationMapping(_ mapping: [Int: [String]]) -> [Int: [String]] {
        mapping
    }

    static func sectionMarkers(
        for pack: PopTrackerLoadedPack,
        mapName: String,
        checkedSectionPaths: Set<String>,
        checkedLocationIDs: Set<Int>
    ) -> [PopTrackerSectionMarker] {
        var markers: [PopTrackerSectionMarker] = []
        collectMarkers(
            nodes: pack.locations,
            parentPath: "",
            mapName: mapName,
            checkedSectionPaths: checkedSectionPaths,
            checkedLocationIDs: checkedLocationIDs,
            pack: pack,
            into: &markers
        )
        return markers
    }

    private static func collectMarkers(
        nodes: [PopTrackerLocationNode],
        parentPath: String,
        mapName: String,
        checkedSectionPaths: Set<String>,
        checkedLocationIDs: Set<Int>,
        pack: PopTrackerLoadedPack,
        into markers: inout [PopTrackerSectionMarker]
    ) {
        for node in nodes {
            let nodePath = parentPath.isEmpty ? node.name : "\(parentPath)/\(node.name)"
            if let sections = node.sections {
                for section in sections {
                    let sectionPath = "\(nodePath)/\(section.name)"
                    let apLocationID = pack.apLocationID(forSectionPath: sectionPath)
                    let checkedByPath = checkedSectionPaths.contains(sectionPath)
                    let checkedByAP = apLocationID.map { checkedLocationIDs.contains($0) } ?? false
                    let checked = checkedByPath || checkedByAP
                    for mapLocation in node.mapLocations ?? [] where mapLocation.map == mapName {
                        markers.append(PopTrackerSectionMarker(
                            id: sectionPath,
                            locationName: node.name,
                            mapName: mapName,
                            x: mapLocation.x,
                            y: mapLocation.y,
                            checked: checked,
                            apLocationID: apLocationID
                        ))
                    }
                }
            }
            if let children = node.children {
                collectMarkers(
                    nodes: children,
                    parentPath: nodePath,
                    mapName: mapName,
                    checkedSectionPaths: checkedSectionPaths,
                    checkedLocationIDs: checkedLocationIDs,
                    pack: pack,
                    into: &markers
                )
            }
        }
    }
}
