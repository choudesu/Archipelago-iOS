import Foundation

enum PopTrackerPackInstaller {
    static func install(from sourceURL: URL, packsRootURL: URL) throws -> PopTrackerInstalledPack {
        let fileManager = FileManager.default
        let stagingURL = fileManager.temporaryDirectory
            .appendingPathComponent("poptracker-import-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: stagingURL) }

        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory), isDirectory.boolValue {
            try copyDirectory(from: sourceURL, to: stagingURL, fileManager: fileManager)
        } else {
            try ZipExtractor.extract(zipURL: sourceURL, to: stagingURL)
        }

        let packRoot = try resolvePackRoot(in: stagingURL, fileManager: fileManager)
        let manifestURL = packRoot.appendingPathComponent("manifest.json")
        let manifestText = try String(contentsOf: manifestURL, encoding: .utf8)
        let manifest = try JSONC.decode(PopTrackerManifest.self, from: manifestText)

        let uid = manifest.packageUID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !uid.isEmpty else {
            throw PopTrackerPackError.installFailed("Pack is missing package_uid.")
        }

        let destination = packsRootURL.appendingPathComponent(uid, isDirectory: true)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.createDirectory(at: packsRootURL, withIntermediateDirectories: true)
        if packRoot == stagingURL {
            try fileManager.copyItem(at: stagingURL, to: destination)
        } else {
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
            try copyDirectory(from: packRoot, to: destination, fileManager: fileManager)
        }

        return PopTrackerInstalledPack(
            packageUID: uid,
            name: manifest.name,
            gameName: manifest.gameName.trimmingCharacters(in: .whitespacesAndNewlines),
            packageVersion: manifest.packageVersion,
            installedAt: Date(),
            variants: Array(manifest.variants.keys).sorted()
        )
    }

    private static func copyDirectory(from source: URL, to destination: URL, fileManager: FileManager) throws {
        let contents = try fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
        for item in contents {
            let target = destination.appendingPathComponent(item.lastPathComponent)
            try fileManager.copyItem(at: item, to: target)
        }
    }

    private static func resolvePackRoot(in stagingURL: URL, fileManager: FileManager) throws -> URL {
        let manifestAtRoot = stagingURL.appendingPathComponent("manifest.json")
        if fileManager.fileExists(atPath: manifestAtRoot.path) {
            return stagingURL
        }

        let contents = try fileManager.contentsOfDirectory(
            at: stagingURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        for item in contents {
            let isDirectory = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            guard isDirectory else { continue }
            let manifestURL = item.appendingPathComponent("manifest.json")
            if fileManager.fileExists(atPath: manifestURL.path) {
                return item
            }
        }

        throw PopTrackerPackError.missingManifest
    }
}
