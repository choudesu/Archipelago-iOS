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
    @Published var loadedBookmarkName: String?

    let commands: APClientCommands
    let bookmarkStore: ConnectionBookmarkStore

    init(bookmarkStore: ConnectionBookmarkStore = .shared) {
        let context = APContext()
        self.context = context
        self.commands = APClientCommands(context: context)
        self.bookmarkStore = bookmarkStore
        context.commandProcessor = self.commands
        context.delegate = self
        if Persistence.deathLinkEnabled {
            context.tags.insert("DeathLink")
        }
        context.appendLog("Archipelago iOS client ready. Enter a server address and tap Connect.")
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
        loadedBookmarkName = bookmark.name
        selectedTab = 0
    }

    func clearLoadedBookmarkPreview() {
        loadedBookmarkName = nil
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

    func submitPromptInput() {
        guard context.awaitingInputPrompt != nil else { return }
        let text = commandText
        commandText = ""
        context.submitUserInput(text)
    }
}
