import SwiftUI

@MainActor
final class AppViewModel: ObservableObject, APContextDelegate {
    @Published private(set) var activeSessionID: UUID
    @Published var commandText = ""
    @Published var selectedTab = 0
    @Published var errorTitle: String?
    @Published var errorMessage: String?
    @Published var showError = false
    @Published var commandHistory: [String] = []
    @Published var historyIndex = -1

    let sessionManager: ConnectionSessionManager
    let commands: APClientCommands
    let bookmarkStore: ConnectionBookmarkStore
    let inAppNotifications: InAppNotificationCenter
    let activityRouter: ActivityNotificationRouter
    let packStore: PopTrackerPackStore
    let trackerBridge: APTrackerBridge

    var context: APContext { sessionManager.activeContext }

    init(bookmarkStore: ConnectionBookmarkStore = .shared, packStore: PopTrackerPackStore = .shared) {
        let sessionManager = ConnectionSessionManager()
        let inAppNotifications = InAppNotificationCenter()
        let activityRouter = ActivityNotificationRouter(inAppCenter: inAppNotifications)
        let context = sessionManager.activeContext
        self.sessionManager = sessionManager
        self.activeSessionID = sessionManager.activeSessionID
        self.inAppNotifications = inAppNotifications
        self.activityRouter = activityRouter
        self.commands = APClientCommands(context: context)
        self.bookmarkStore = bookmarkStore
        self.packStore = packStore
        self.trackerBridge = APTrackerBridge(context: context, packStore: packStore)
        wireAllSessions()
        packStore.applyPackToContext(context)
        if Persistence.deathLinkEnabled, Persistence.clientMode == .text {
            context.tags.insert("DeathLink")
        }
        context.appendLog("Applepelago ready. Enter a server address and tap Connect.")
    }

    func selectSession(_ id: UUID) {
        guard id != activeSessionID else { return }
        sessionManager.setActiveSession(id: id)
        activeSessionID = id
        rebindActiveSession()
        objectWillChange.send()
    }

    func addSession() {
        let session = sessionManager.addSession()
        wireContext(sessionManager.context(for: session.id))
        selectSession(session.id)
        objectWillChange.send()
    }

    func removeSession(_ id: UUID) {
        sessionManager.removeSession(id: id)
        activeSessionID = sessionManager.activeSessionID
        rebindActiveSession()
        objectWillChange.send()
    }

    func setPrimarySession(_ id: UUID) {
        sessionManager.setPrimarySession(id: id)
        objectWillChange.send()
    }

    private func wireAllSessions() {
        for context in sessionManager.contexts.values {
            wireContext(context)
        }
        rebindActiveSession()
    }

    private func wireContext(_ context: APContext?) {
        guard let context else { return }
        sessionManager.wireContext(
            context,
            delegate: self,
            activityRouter: context.sessionID == activeSessionID ? activityRouter : nil,
            commandProcessor: commands
        )
    }

    private func rebindActiveSession() {
        let context = sessionManager.activeContext
        commands.bind(to: context)
        trackerBridge.bind(to: context)
        for sessionContext in sessionManager.contexts.values {
            sessionContext.activityRouter = sessionContext.sessionID == activeSessionID ? activityRouter : nil
        }
        packStore.applyPackToContext(context)
        packStore.validateGameMatch(sessionGame: context.activeGameName)
        objectWillChange.send()
    }

    func setClientMode(_ mode: ClientMode) {
        Persistence.clientMode = mode
        sessionManager.reloadContextConfiguration(mode: mode, trackerGame: Persistence.trackerConnectGame)
        packStore.applyPackToContext(context)
    }

    func importPopTrackerPack(from url: URL) async {
        do {
            let install = try await packStore.importPack(from: url)
            try applyImportedPack(install)
        } catch {
            presentError("Import Failed", error.localizedDescription)
        }
    }

    private func applyImportedPack(_ install: PopTrackerInstalledPack) throws {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        try withTransaction(transaction) {
            try packStore.setActivePack(uid: install.packageUID)
            packStore.applyPackToContext(context)
            if Persistence.clientMode != .tracker {
                setClientMode(.tracker)
            }
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
        sessionManager.syncSessionMetadata(from: context)
        sessionManager.connect()
    }

    func disconnect() {
        sessionManager.disconnect()
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
        sessionManager.syncSessionMetadata(from: context)
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
        sessionManager.syncSessionMetadata(from: context)
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
        guard context.sessionID == activeSessionID else { return "" }
        return ""
    }

    func contextDidUpdateHints(_ context: APContext) {
        objectWillChange.send()
    }

    func contextDidUpdateProgress(_ context: APContext) {
        objectWillChange.send()
    }

    func contextDidConnect(_ context: APContext) {
        sessionManager.syncSessionMetadata(from: context)
        if context.sessionID == sessionManager.primarySessionID {
            sessionManager.syncPrimaryBackgroundCredentials(from: context)
        }
        objectWillChange.send()
        if context.sessionID == activeSessionID {
            BackgroundRefreshTask.schedule()
            packStore.applyPackToContext(context)
            packStore.validateGameMatch(sessionGame: context.activeGameName)
            trackerBridge.handleConnect()
        }
    }

    func contextDidReceiveSlotData(_ context: APContext, slotData: [String: Any]) {
        guard context.sessionID == activeSessionID else { return }
        objectWillChange.send()
        trackerBridge.handleSlotData(slotData)
    }

    func contextDidUpdateCheckedLocations(_ context: APContext, locationIDs: Set<Int>) {
        guard context.sessionID == activeSessionID else { return }
        objectWillChange.send()
        trackerBridge.handleCheckedLocations(locationIDs)
    }

    func contextDidReceiveItems(_ context: APContext, items: [NetworkItem]) {
        guard context.sessionID == activeSessionID else { return }
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
