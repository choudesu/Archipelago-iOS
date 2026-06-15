import SwiftUI

@MainActor
final class AppViewModel: ObservableObject, APContextDelegate {
    @Published var context: APContext
    @Published var commandText = ""
    @Published var selectedTab = 0
    @Published var errorTitle: String?
    @Published var errorMessage: String?
    @Published var showError = false
    @Published var commandHistory: [String] = []
    @Published var historyIndex = -1

    let commands: APClientCommands
    let bookmarkStore: ConnectionBookmarkStore
    let inAppNotifications: InAppNotificationCenter
    let activityRouter: ActivityNotificationRouter
    let packStore: PopTrackerPackStore
    let trackerBridge: APTrackerBridge

    init(bookmarkStore: ConnectionBookmarkStore = .shared, packStore: PopTrackerPackStore = .shared) {
        let context = APContext()
        let inAppNotifications = InAppNotificationCenter()
        let activityRouter = ActivityNotificationRouter(inAppCenter: inAppNotifications)
        self.context = context
        self.inAppNotifications = inAppNotifications
        self.activityRouter = activityRouter
        self.commands = APClientCommands(context: context)
        self.bookmarkStore = bookmarkStore
        self.packStore = packStore
        context.commandProcessor = self.commands
        context.delegate = self
        context.activityRouter = activityRouter
        self.trackerBridge = APTrackerBridge(context: context, packStore: packStore)
        context.applyClientMode(Persistence.clientMode)
        context.trackerConnectGame = Persistence.trackerConnectGame
        packStore.applyPackToContext(context)
        if Persistence.deathLinkEnabled, Persistence.clientMode == .text {
            context.tags.insert("DeathLink")
        }
        context.appendLog("Applepelago ready. Enter a server address and tap Connect.")
    }

    func setClientMode(_ mode: ClientMode) {
        Persistence.clientMode = mode
        context.applyClientMode(mode)
        if Persistence.deathLinkEnabled, mode == .text {
            context.tags.insert("DeathLink")
        }
    }

    func importPopTrackerPack(from url: URL) throws {
        let install = try packStore.importPack(from: url)
        try packStore.setActivePack(uid: install.packageUID)
        packStore.applyPackToContext(context)
        if Persistence.clientMode != .tracker {
            setClientMode(.tracker)
        }
    }

    func setActivePopTrackerPack(uid: String?) throws {
        try packStore.setActivePack(uid: uid)
        packStore.applyPackToContext(context)
    }

    func removePopTrackerPack(uid: String) throws {
        try packStore.removePack(uid: uid)
    }

    func connect() {
        var address = context.displayAddress.isEmpty ? context.suggestedAddress : context.displayAddress
        if let parsed = try? ServerURLParser.parse(address) {
            if let user = parsed.username {
                context.setSlotName(user)
            }
            address = parsed.displayAddress
            context.displayAddress = address
        }
        context.serverAddress = address
        context.connect()
    }

    func disconnect() {
        context.disconnect()
    }

    func currentServerAddress() -> String {
        let address = context.displayAddress.isEmpty ? context.suggestedAddress : context.displayAddress
        return address.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func currentSlotName() -> String {
        context.slotName
    }

    func currentPassword() -> String? {
        context.password
    }

    func suggestedBookmarkName() -> String {
        let address = currentServerAddress()
        let slot = currentSlotName()
        if address.isEmpty {
            return slot.isEmpty ? "Bookmark" : slot
        }
        if slot.isEmpty {
            return address
        }
        return "\(slot)@\(address)"
    }

    func loadBookmark(_ bookmark: ConnectionBookmark) {
        guard canLoadBookmark else { return }

        var server = bookmark.serverAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        var slot = bookmark.slotName.trimmingCharacters(in: .whitespacesAndNewlines)
        var password = bookmarkStore.password(for: bookmark.id)

        if let parsed = try? ServerURLParser.parse(server) {
            if let user = parsed.username, slot.isEmpty {
                slot = user
            }
            if let pass = parsed.password {
                password = pass
            }
            server = parsed.displayAddress
        }

        context.displayAddress = server
        context.serverAddress = server
        if slot.isEmpty {
            context.setSlotName(nil)
        } else {
            context.setSlotName(slot)
        }
        context.password = password
        selectedTab = 0
    }

    var canLoadBookmark: Bool {
        !context.isConnected && context.connectionState != .connecting
    }

    func saveBookmark(name: String, serverAddress: String, slotName: String, password: String?) {
        bookmarkStore.add(
            name: name,
            serverAddress: serverAddress,
            slotName: slotName,
            password: password
        )
    }

    func updateBookmark(
        _ bookmark: ConnectionBookmark,
        name: String,
        serverAddress: String,
        slotName: String,
        password: String?
    ) {
        let updated = ConnectionBookmark(
            id: bookmark.id,
            name: name,
            serverAddress: serverAddress,
            slotName: slotName,
            createdAt: bookmark.createdAt
        )
        bookmarkStore.update(updated, password: password)
    }

    func deleteBookmark(_ bookmark: ConnectionBookmark) {
        bookmarkStore.delete(bookmark)
    }

    func makeExportDocument() throws -> ConnectionBookmarksDocument {
        guard !bookmarkStore.bookmarks.isEmpty else {
            throw ConnectionBookmarkTransferError.nothingToExport
        }
        return ConnectionBookmarksDocument(data: try bookmarkStore.exportData())
    }

    func readBookmarkImportData(from url: URL) throws -> Data {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try Data(contentsOf: url)
    }

    func countImportableBookmarks(in data: Data) throws -> Int {
        let items = try ConnectionBookmarkTransfer.decode(data)
        return items.filter { item in
            !item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !item.serverAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.count
    }

    @discardableResult
    func importBookmarks(data: Data, replace: Bool) throws -> Int {
        try bookmarkStore.importBookmarks(
            from: data,
            mode: replace ? .replace : .merge
        )
    }

    func presentError(_ title: String, _ message: String) {
        errorTitle = title
        errorMessage = message
        showError = true
    }

    func submitInput() {
        let text = commandText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        if context.awaitingInputPrompt != nil {
            context.submitUserInput(text)
            commandText = ""
            return
        }

        if text.hasPrefix("/") {
            context.appendLog(text, isCommandEcho: true)
            _ = commands.process(text)
        } else {
            if text.hasPrefix("!") {
                context.appendLog(text, isCommandEcho: true)
            }
            context.sendSay(text)
        }

        if text.hasPrefix("/") || text.hasPrefix("!") {
            commandHistory.insert(text, at: 0)
            if commandHistory.count > 50 {
                commandHistory.removeLast()
            }
        }
        historyIndex = -1
        commandText = ""
    }

    func historyUp() {
        guard !commandHistory.isEmpty else { return }
        historyIndex = min(historyIndex + 1, commandHistory.count - 1)
        commandText = commandHistory[historyIndex]
    }

    func historyDown() {
        guard historyIndex > 0 else {
            historyIndex = -1
            commandText = ""
            return
        }
        historyIndex -= 1
        commandText = commandHistory[historyIndex]
    }

    // MARK: - APContextDelegate

    func contextDidUpdateConnectionState(_ context: APContext) {
        objectWillChange.send()
    }

    func contextDidReceiveLog(_ context: APContext, entry: ChatLogEntry) {
        objectWillChange.send()
    }

    func contextDidReceiveError(_ context: APContext, title: String, message: String) {
        errorTitle = title
        errorMessage = message
        showError = true
    }

    func contextNeedsUserInput(_ context: APContext, prompt: String) async -> String {
        ""
    }

    func contextDidUpdateHints(_ context: APContext) {
        objectWillChange.send()
    }

    func contextDidUpdateProgress(_ context: APContext) {
        objectWillChange.send()
    }

    func contextDidConnect(_ context: APContext) {
        objectWillChange.send()
        BackgroundRefreshTask.schedule()
        packStore.applyPackToContext(context)
        packStore.validateGameMatch(sessionGame: context.activeGameName)
        trackerBridge.handleConnect()
    }

    func contextDidReceiveSlotData(_ context: APContext, slotData: [String: Any]) {
        objectWillChange.send()
        trackerBridge.handleSlotData(slotData)
    }

    func contextDidUpdateCheckedLocations(_ context: APContext, locationIDs: Set<Int>) {
        objectWillChange.send()
        trackerBridge.handleCheckedLocations(locationIDs)
    }

    func contextDidReceiveItems(_ context: APContext, items: [NetworkItem]) {
        objectWillChange.send()
        trackerBridge.handleReceivedItems(items)
    }

    func submitPromptInput() {
        guard context.awaitingInputPrompt != nil else { return }
        let text = commandText
        commandText = ""
        context.submitUserInput(text)
    }
}
