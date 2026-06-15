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
    @Published var debugLog: [String] = []

    let commands: APClientCommands
    let bookmarkStore: ConnectionBookmarkStore
    let inAppNotifications: InAppNotificationCenter
    let activityRouter: ActivityNotificationRouter

    init(bookmarkStore: ConnectionBookmarkStore = .shared) {
        let context = APContext()
        let inAppNotifications = InAppNotificationCenter()
        let activityRouter = ActivityNotificationRouter(inAppCenter: inAppNotifications)
        self.context = context
        self.inAppNotifications = inAppNotifications
        self.activityRouter = activityRouter
        self.commands = APClientCommands(context: context)
        self.bookmarkStore = bookmarkStore
        context.commandProcessor = self.commands
        context.delegate = self
        context.activityRouter = activityRouter
        if Persistence.deathLinkEnabled {
            context.tags.insert("DeathLink")
        }
        context.appendLog("Applepelago ready. Enter a server address and tap Connect.")
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
        debugNote("Connected; background refresh scheduled")
    }

    // MARK: - Debug tools

    func debugNote(_ message: String) {
        guard Persistence.debugModeEnabled else { return }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let line = "[\(formatter.string(from: Date()))] \(message)"
        debugLog.insert(line, at: 0)
        if debugLog.count > 30 {
            debugLog.removeLast()
        }
    }

    func debugClearLog() {
        debugLog = []
    }

    func debugSimulateItemBanner() {
        let event = ActivityDebugService.simulateItemAlert(context: context, router: activityRouter)
        debugNote("Item banner: \(event.message)")
    }

    func debugSimulateHintBanner() {
        let event = ActivityDebugService.simulateHintAlert(context: context, router: activityRouter)
        debugNote("Hint banner: \(event.message)")
    }

    func debugClearRouterDedup() {
        ActivityDebugService.clearRouterDedup(activityRouter)
        debugNote("Cleared router dedup cache")
    }

    func debugSimulateBackgroundItemNotification() {
        ActivityDebugService.simulateBackgroundIOSNotification(router: activityRouter, kind: .item)
        debugNote("Scheduled simulated background item notification")
    }

    func debugSimulateBackgroundHintNotification() {
        ActivityDebugService.simulateBackgroundIOSNotification(router: activityRouter, kind: .hint)
        debugNote("Scheduled simulated background hint notification")
    }

    func debugSimulateDisconnectNotification() {
        ActivityDebugService.simulateDisconnectNotification()
        debugNote("Scheduled simulated disconnect notification")
    }

    func debugTriggerReceivedItemsPath() {
        ActivityDebugService.simulateReceivedItemsPath(context: context)
        debugNote("Triggered ReceivedItems path (item count: \(context.itemsReceived.count))")
    }

    func debugTriggerPrintJSONHintPath() {
        ActivityDebugService.simulatePrintJSONHintPath(context: context)
        debugNote("Triggered PrintJSON Hint path")
    }

    func debugTriggerRefreshHintsPath() {
        ActivityDebugService.simulateRefreshHintsPath(context: context)
        debugNote("Triggered refreshHints path (hint count: \(context.hints.count))")
    }

    func debugResetActivitySnapshot() {
        ActivityDebugService.resetActivitySnapshot()
        debugNote("Reset activity snapshot")
    }

    func debugRewindSnapshot() {
        ActivityDebugService.rewindSnapshotForTesting(context: context)
        debugNote("Rewound snapshot for diff testing")
    }

    func debugScheduleNearTermRefresh() {
        let scheduled = ActivityDebugService.scheduleNearTermBackgroundRefresh()
        debugNote(scheduled
            ? "Scheduled near-term BG refresh (~5s)"
            : "Failed to schedule BG refresh (check debug mode and BGTask registration)")
    }

    func debugRunBackgroundSyncNow() async {
        debugNote("Running background sync now...")
        let success = await BackgroundRefreshTask.runSyncNow()
        debugNote(success ? "Background sync finished successfully" : "Background sync failed or skipped")
    }

    func submitPromptInput() {
        guard context.awaitingInputPrompt != nil else { return }
        let text = commandText
        commandText = ""
        context.submitUserInput(text)
    }
}
