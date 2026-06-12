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

    init() {
        let context = APContext()
        self.context = context
        self.commands = APClientCommands(context: context)
        context.commandProcessor = self.commands
        context.delegate = self
        if Persistence.deathLinkEnabled {
            context.tags.insert("DeathLink")
        }
        context.appendLog("Archipelago iOS client ready. Enter a server address and tap Connect.")
    }

    func connect() {
        let address = context.displayAddress.isEmpty ? context.suggestedAddress : context.displayAddress
        context.serverAddress = address
        context.displayAddress = address
        context.connect()
    }

    func disconnect() {
        context.disconnect()
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
