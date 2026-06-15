import Foundation

@MainActor
final class PopTrackerPackStore: ObservableObject {
    static let shared = PopTrackerPackStore()

    @Published private(set) var installedPacks: [PopTrackerInstalledPack] = []
    @Published private(set) var loadedPack: PopTrackerLoadedPack?
    @Published var gameMismatchMessage: String?

    private let fileManager = FileManager.default
    private let indexFileName = "installed.json"

    private var packsRootURL: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("PopTrackerPacks", isDirectory: true)
    }

    private var indexURL: URL {
        packsRootURL.appendingPathComponent(indexFileName)
    }

    private init() {
        loadIndex()
        reloadActivePack()
    }

    func importPack(from zipURL: URL) async throws -> PopTrackerInstalledPack {
        let accessed = zipURL.startAccessingSecurityScopedResource()
        defer {
            if accessed { zipURL.stopAccessingSecurityScopedResource() }
        }

        let packsRoot = packsRootURL
        let install = try await Task.detached(priority: .userInitiated) {
            try PopTrackerPackInstaller.install(from: zipURL, packsRootURL: packsRoot)
        }.value

        upsertInstalledPack(install)
        saveIndex()
        return install
    }

    func removePack(uid: String) throws {
        let destination = packsRootURL.appendingPathComponent(uid, isDirectory: true)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        installedPacks.removeAll { $0.packageUID == uid }
        if Persistence.activePopTrackerPackUID == uid {
            Persistence.activePopTrackerPackUID = nil
            Persistence.activePopTrackerVariantUID = nil
            loadedPack = nil
        }
        saveIndex()
    }

    func setActivePack(uid: String?, variantUID: String? = nil) throws {
        guard let uid else {
            Persistence.activePopTrackerPackUID = nil
            Persistence.activePopTrackerVariantUID = nil
            loadedPack = nil
            gameMismatchMessage = nil
            return
        }
        guard let install = installedPacks.first(where: { $0.packageUID == uid }) else { return }
        let rootURL = packsRootURL.appendingPathComponent(uid, isDirectory: true)
        let manifestURL = rootURL.appendingPathComponent("manifest.json")
        let manifestText = try String(contentsOf: manifestURL, encoding: .utf8)
        let manifest = try JSONC.decode(PopTrackerManifest.self, from: manifestText)
        let resolvedVariant = try PopTrackerVariantResolver.resolveVariant(
            requested: variantUID,
            packUID: uid,
            persistedPackUID: Persistence.activePopTrackerPackUID,
            persistedVariantUID: Persistence.activePopTrackerVariantUID,
            manifest: manifest
        )
        loadedPack = try PopTrackerPackLoader.loadInstalledPack(
            install: install,
            rootURL: rootURL,
            variantUID: resolvedVariant
        )
        Persistence.activePopTrackerPackUID = uid
        Persistence.activePopTrackerVariantUID = resolvedVariant
        gameMismatchMessage = nil
    }

    func reloadActivePack() {
        guard let uid = Persistence.activePopTrackerPackUID else {
            loadedPack = nil
            return
        }
        try? setActivePack(uid: uid)
    }

    func validateGameMatch(sessionGame: String) {
        guard let pack = loadedPack else {
            gameMismatchMessage = nil
            return
        }
        let packGame = pack.gameName
        guard !packGame.isEmpty, !sessionGame.isEmpty, packGame != sessionGame else {
            gameMismatchMessage = nil
            return
        }
        gameMismatchMessage = "Loaded pack is for \"\(packGame)\" but you are connected to \"\(sessionGame)\"."
    }

    func applyPackToContext(_ context: APContext) {
        guard let pack = loadedPack else { return }
        let game = pack.gameName
        if !game.isEmpty {
            context.trackerConnectGame = game
            Persistence.trackerConnectGame = game
        }
    }

    private func upsertInstalledPack(_ install: PopTrackerInstalledPack) {
        if let index = installedPacks.firstIndex(where: { $0.packageUID == install.packageUID }) {
            installedPacks[index] = install
        } else {
            installedPacks.append(install)
        }
        installedPacks.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func loadIndex() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([PopTrackerInstalledPack].self, from: data) else {
            installedPacks = []
            return
        }
        installedPacks = decoded.filter { fileManager.fileExists(atPath: packsRootURL.appendingPathComponent($0.packageUID).path) }
    }

    private func saveIndex() {
        try? fileManager.createDirectory(at: packsRootURL, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(installedPacks) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }
}
