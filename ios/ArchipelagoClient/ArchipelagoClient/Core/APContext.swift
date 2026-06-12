import Foundation

@MainActor
protocol APContextDelegate: AnyObject {
    func contextDidUpdateConnectionState(_ context: APContext)
    func contextDidReceiveLog(_ context: APContext, entry: ChatLogEntry)
    func contextDidReceiveError(_ context: APContext, title: String, message: String)
    func contextNeedsUserInput(_ context: APContext, prompt: String) async -> String
    func contextDidUpdateHints(_ context: APContext)
    func contextDidUpdateProgress(_ context: APContext)
}

@MainActor
final class APContext: ObservableObject {
    weak var delegate: APContextDelegate?

    // Connection
    @Published var connectionState: ConnectionState = .disconnected
    @Published var serverAddress: String
    @Published var displayAddress: String = ""
    @Published var password: String?
    @Published var auth: String?
    @Published var username: String?

    // Server state
    @Published var serverVersion = APVersion(major: 0, minor: 0, build: 0)
    @Published var generatorVersion = APVersion(major: 0, minor: 0, build: 0)
    @Published var team: Int?
    @Published var slot: Int?
    @Published var hintCost: Int?
    @Published var hintPoints: Int?
    @Published var checkPoints: Int?
    @Published var game: String = ""
    @Published var seedName: String?
    @Published var finishedGame = false
    @Published var ready = false
    @Published var currentEnergyLinkValue: Int?
    @Published var permissions: [String: String] = [
        "release": "disabled",
        "collect": "disabled",
        "remaining": "disabled"
    ]

    var tags: Set<String> = ["AP", "TextOnly"]
    var itemsHandling = 0b111
    var wantSlotData = false

    var slotInfo: [Int: NetworkSlot] = [0: NetworkSlot(name: "Archipelago", game: "Archipelago", type: SlotType.player.rawValue)]
    var playerNames: [Int: String] = [0: "Archipelago"]
    var itemsReceived: [NetworkItem] = []
    var missingLocations: Set<Int> = []
    var checkedLocations: Set<Int> = []
    var serverLocations: Set<Int> = []
    var locationsChecked: Set<Int> = []
    var locationsScouted: Set<Int> = []
    var locationsInfo: [Int: NetworkItem] = [:]
    var storedData: [String: Any] = [:]
    var storedDataNotificationKeys: Set<String> = []
    var lastDeathLink: TimeInterval = Date().timeIntervalSince1970

    let nameLookup = NameLookup()

    @Published private(set) var chatLog: [ChatLogEntry] = []
    @Published private(set) var hints: [HintEntry] = []
    @Published var awaitingInputPrompt: String?

    private var webSocket: APWebSocketSession?
    private var messageHandler: APServerMessageHandler?
    private var keepAliveTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var connectionGeneration = 0
    private var awaitingConnectResponse = false
    private var connectionRefusedHandled = false
    private var disconnectedIntentionally = false
    private var currentReconnectDelay = 5
    private let startingReconnectDelay = 5
    private var inputContinuation: CheckedContinuation<String, Never>?

    var commandProcessor: APClientCommands?

    var isConnected: Bool { connectionState == .connected && webSocket?.isOpen == true }
    var suggestedAddress: String { serverAddress.isEmpty ? Persistence.lastServerAddress : serverAddress }

    var totalLocations: Int? {
        if checkedLocations.isEmpty && missingLocations.isEmpty { return nil }
        return checkedLocations.union(missingLocations).count
    }

    var progressValue: Double {
        guard let total = totalLocations, total > 0 else { return 0 }
        return Double(checkedLocations.count) / Double(total)
    }

    init(serverAddress: String = "", password: String? = nil) {
        self.serverAddress = serverAddress
        self.password = password
        self.messageHandler = APServerMessageHandler(context: self)
    }

    func slotConcernsSelf(_ slot: Int) -> Bool {
        guard let mySlot = self.slot else { return false }
        if slot == mySlot { return true }
        if let info = slotInfo[slot] {
            return info.groupMembers.contains(mySlot)
        }
        return false
    }

    func connect(address: String? = nil) {
        Task { await connectAsync(address: address) }
    }

    func disconnect(allowAutoreconnect: Bool = false) {
        Task { await disconnectAsync(allowAutoreconnect: allowAutoreconnect) }
    }

    func sendMessages(_ messages: [[String: Any]]) async {
        guard let webSocket, webSocket.isOpen else {
            appendLog("Cannot send — WebSocket is not connected.")
            return
        }
        do {
            let encoded = try APCodec.encode(messages)
            try await webSocket.send(encoded)
        } catch {
            appendLog("Failed to send message: \(error.localizedDescription)")
        }
    }

    func sendSay(_ text: String) {
        Task {
            await sendMessages([["cmd": "Say", "text": text]])
        }
    }

    func updateHint(location: Int, findingPlayer: Int, status: HintStatus?) {
        var message: [String: Any] = [
            "cmd": "UpdateHint",
            "location": location,
            "player": findingPlayer
        ]
        if let status {
            message["status"] = status.rawValue
        }
        Task { await sendMessages([message]) }
    }

    func updateDeathLink(_ enabled: Bool) {
        if enabled {
            tags.insert("DeathLink")
        } else {
            tags.remove("DeathLink")
        }
        Persistence.deathLinkEnabled = enabled
        guard isConnected else { return }
        Task {
            await sendMessages([["cmd": "ConnectUpdate", "tags": Array(tags).sorted()]])
        }
    }

    func appendLog(_ text: String, parts: [JSONMessagePart] = [], isCommandEcho: Bool = false) {
        let entry = ChatLogEntry(text: text, parts: parts, isCommandEcho: isCommandEcho)
        chatLog.append(entry)
        objectWillChange.send()
        delegate?.contextDidReceiveLog(self, entry: entry)
    }

    func refreshHints() {
        guard let team, let slot else {
            hints = []
            return
        }
        let key = "_read_hints_\(team)_\(slot)"
        if let raw = storedData[key] as? [[String: Any]] {
            hints = raw.map { HintEntry(from: $0) }
        } else {
            hints = []
        }
        delegate?.contextDidUpdateHints(self)
    }

    func markConnectionRefusedHandled() {
        connectionRefusedHandled = true
        awaitingConnectResponse = false
    }

    func markConnectSucceeded() {
        awaitingConnectResponse = false
        connectionRefusedHandled = false
    }

    // MARK: - Internal handlers used by APServerMessageHandler

    func resetServerState() {
        slot = nil
        team = nil
        itemsReceived = []
        locationsInfo = [:]
        serverVersion = APVersion(major: 0, minor: 0, build: 0)
        generatorVersion = APVersion(major: 0, minor: 0, build: 0)
        hintCost = nil
        permissions = [
            "release": "disabled",
            "collect": "disabled",
            "remaining": "disabled"
        ]
    }

    func consumePlayersPackage(_ players: Any) {
        guard let team else { return }
        playerNames = [0: "Archipelago"]
        if let playerList = players as? [NetworkPlayer] {
            for player in playerList where player.team == team {
                playerNames[player.slot] = player.alias
            }
        } else if let playerList = players as? [[String: Any]] {
            for dict in playerList {
                let playerTeam = dict["team"] as? Int ?? 0
                let playerSlot = dict["slot"] as? Int ?? 0
                let alias = dict["alias"] as? String ?? dict["name"] as? String ?? "Player \(playerSlot)"
                if playerTeam == team {
                    playerNames[playerSlot] = alias
                }
            }
        }
    }

    func updatePermissions(_ raw: [String: Any]) {
        for (name, value) in raw {
            if let intValue = value as? Int {
                permissions[name] = permissionName(intValue)
            }
        }
    }

    func consumeNetworkDataPackage(_ data: [String: Any]) {
        guard let games = data["games"] as? [String: [String: Any]] else { return }
        for (game, gameData) in games {
            if let json = try? JSONSerialization.data(withJSONObject: gameData),
               let package = try? JSONDecoder().decode(GamesPackage.self, from: json) {
                DataPackageCache.shared.store(package: package, game: game)
                nameLookup.updateGame(package, game: game)
            }
        }
        appendLog("Got new ID/Name DataPackage for \(games.keys.sorted().joined(separator: ", "))")
    }

    func prepareDataPackage(relevantGames: Set<String>, remoteChecksums: [String: String]) async {
        let needed = DataPackageCache.shared.gamesNeedingUpdate(
            relevantGames: relevantGames,
            remoteChecksums: remoteChecksums
        )
        guard !needed.isEmpty else { return }
        let messages = needed.map { ["cmd": "GetDataPackage", "games": [$0]] as [String: Any] }
        await sendMessages(messages)
    }

    func serverAuth(passwordRequested: Bool) async {
        if passwordRequested, password == nil {
            let entered = await requestUserInput(prompt: "Enter the password required to join this game:")
            password = entered.trimmingCharacters(in: .whitespacesAndNewlines)
            password = password?.isEmpty == true ? nil : password
            await sendConnect()
            return
        }
        await getUsername()
    }

    func getUsername() async {
        if auth == nil {
            auth = username?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if auth == nil {
            let entered = await requestUserInput(prompt: "Enter slot name:")
            auth = entered.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let name = auth, !name.isEmpty else {
            appendLog("Slot name cannot be empty.")
            auth = nil
            await getUsername()
            return
        }
        auth = name
        await sendConnect()
    }

    func sendConnect(extra: [String: Any] = [:]) async {
        guard let name = auth, !name.isEmpty else {
            appendLog("Cannot connect without a slot name.")
            return
        }

        // Match Python CommonClient: always send the client protocol version as a Version object.
        let connectVersion = APVersion.clientVersion

        appendLog("Connecting as \"\(name)\" (protocol \(connectVersion.simpleString))...")

        awaitingConnectResponse = true
        connectionRefusedHandled = false

        var payload: [String: Any] = [
            "cmd": "Connect",
            "password": password ?? NSNull(),
            "name": name,
            "version": connectVersion,
            "tags": Array(tags).sorted(),
            "items_handling": itemsHandling,
            "uuid": Persistence.clientUUID,
            "game": "",
            "slot_data": wantSlotData
        ]
        for (key, value) in extra {
            payload[key] = value
        }
        await sendMessages([payload])
    }

    func onPrintJSON(_ args: [String: Any]) {
        let parts = decodeMessageParts(args["data"])
        let renderer = JSONMessageRenderer(
            playerNames: playerNames,
            nameLookup: nameLookup,
            slot: slot,
            slotInfo: slotInfo
        )
        appendLog(renderer.render(parts), parts: parts)
    }

    func onPrint(_ args: [String: Any]) {
        if let text = args["text"] as? String {
            appendLog(text)
        }
    }

    func onDeathLink(_ data: [String: Any]) {
        let time = data["time"] as? TimeInterval ?? Date().timeIntervalSince1970
        lastDeathLink = max(time, lastDeathLink)
        if let cause = data["cause"] as? String, !cause.isEmpty {
            appendLog("DeathLink: \(cause)")
        } else if let source = data["source"] {
            appendLog("DeathLink: Received from \(source)")
        } else {
            appendLog("DeathLink: Received")
        }
    }

    func onPackage(cmd: String, args: [String: Any]) {
        if cmd == "Connected" {
            if game.isEmpty, let slot, let info = slotInfo[slot] {
                game = info.game
            }
        }
    }

    func handleConnectionLoss(_ message: String) {
        connectionState = .disconnected
        delegate?.contextDidUpdateConnectionState(self)
        delegate?.contextDidReceiveError(self, title: "Connection Lost", message: message)
        appendLog(message)
    }

    private func requestUserInput(prompt: String) async -> String {
        awaitingInputPrompt = prompt
        appendLog(prompt)
        return await withCheckedContinuation { continuation in
            inputContinuation = continuation
        }
    }

    func submitUserInput(_ text: String) {
        awaitingInputPrompt = nil
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let continuation = inputContinuation {
            inputContinuation = nil
            continuation.resume(returning: trimmed)
        }
    }

    private func permissionName(_ value: Int) -> String {
        switch value {
        case 0: return "disabled"
        case 1: return "enabled"
        case 2: return "goal"
        case 6: return "auto"
        case 7: return "auto_enabled"
        default: return "unknown"
        }
    }

    private func decodeMessageParts(_ value: Any?) -> [JSONMessagePart] {
        guard let array = value as? [[String: Any]] else { return [] }
        return array.compactMap { dict in
            try? JSONDecoder().decode(JSONMessagePart.self, from: JSONSerialization.data(withJSONObject: dict))
        }
    }

    // MARK: - Connection lifecycle

    private func connectAsync(address: String?) async {
        await disconnectAsync(allowAutoreconnect: true)
        disconnectedIntentionally = false

        let target = (address?.isEmpty == false ? address : nil) ?? (serverAddress.isEmpty ? nil : serverAddress)
        guard let target, !target.isEmpty else {
            appendLog("Please connect to an Archipelago server.")
            return
        }

        connectionState = .connecting
        delegate?.contextDidUpdateConnectionState(self)

        do {
            let parsed = try ServerURLParser.parse(target)
            if let user = parsed.username { username = user }
            if let pass = parsed.password { password = pass }
            displayAddress = parsed.displayAddress
            serverAddress = parsed.displayAddress
            Persistence.lastServerAddress = parsed.displayAddress

            let candidates = ServerURLParser.connectionCandidates(parsed)
            var lastError: Error?

            for (index, candidate) in candidates.enumerated() {
                if index == 0 {
                    appendLog("Connecting to \(candidate.websocketURL.absoluteString)...")
                } else {
                    appendLog("Retrying with \(candidate.websocketURL.absoluteString)...")
                }

                do {
                    try await openWebSocket(parsed: candidate)
                    connectionState = .connected
                    currentReconnectDelay = startingReconnectDelay
                    delegate?.contextDidUpdateConnectionState(self)
                    startKeepAlive()
                    return
                } catch {
                    lastError = error
                    appendLog("Attempt failed: \(error.localizedDescription)")
                    teardownActiveWebSocket()
                }
            }

            throw lastError ?? APWebSocketError.connectionFailed("All connection attempts failed")
        } catch {
            connectionState = .disconnected
            delegate?.contextDidUpdateConnectionState(self)
            handleConnectionLoss("Failed to connect to the multiworld server: \(error.localizedDescription)")
            scheduleReconnect()
        }
    }

    private func openWebSocket(parsed: ParsedServerURL) async throws {
        connectionGeneration += 1
        let generation = connectionGeneration

        let session = APWebSocketSession(url: parsed.websocketURL)
        webSocket = session
        session.onMessage = { [weak self] text in
            Task { @MainActor in
                guard let self, self.connectionGeneration == generation else { return }
                await self.handleIncoming(text)
            }
        }
        session.onClose = { [weak self] error in
            Task { @MainActor in
                // Allow any in-flight server messages (e.g. ConnectionRefused) to process first.
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard let self, self.connectionGeneration == generation else { return }
                await self.handleSocketClosed(error: error)
            }
        }

        try await session.open()
        guard connectionGeneration == generation else {
            throw APWebSocketError.closed
        }
        appendLog("WebSocket connected to \(parsed.websocketURL.absoluteString)")
    }

    private func teardownActiveWebSocket() {
        connectionGeneration += 1
        webSocket?.close()
        webSocket = nil
    }

    private func disconnectAsync(allowAutoreconnect: Bool = false) async {
        if !allowAutoreconnect {
            disconnectedIntentionally = true
            reconnectTask?.cancel()
            reconnectTask = nil
        }
        keepAliveTask?.cancel()
        keepAliveTask = nil
        teardownActiveWebSocket()
        resetServerState()
        connectionState = .disconnected
        delegate?.contextDidUpdateConnectionState(self)
    }

    private func handleIncoming(_ text: String) async {
        do {
            let messages = try APCodec.decode(text)
            for message in messages {
                if let cmd = message["cmd"] as? String, cmd != "DataPackage" {
                    appendLog("← \(cmd)")
                }
                do {
                    await messageHandler?.handle(message)
                } catch {
                    appendLog("Error handling server message: \(error.localizedDescription)")
                }
            }
        } catch {
            appendLog("Failed to decode server message (\(text.prefix(120))): \(error.localizedDescription)")
        }
    }

    private func handleSocketClosed(error: Error?) async {
        if connectionRefusedHandled {
            connectionRefusedHandled = false
            awaitingConnectResponse = false
            return
        }

        let wasJoined = slot != nil
        let savedAuth = auth

        keepAliveTask?.cancel()
        keepAliveTask = nil
        webSocket = nil
        resetServerState()
        awaitingConnectResponse = false
        connectionState = .disconnected
        delegate?.contextDidUpdateConnectionState(self)

        if !wasJoined, let savedAuth, !savedAuth.isEmpty {
            auth = savedAuth
            appendLog("Connection closed before joining as \"\(savedAuth)\". Verify the slot name matches your YAML, then tap Connect to try again.")
        } else if let error {
            let hint = wasJoined && !serverAddress.isEmpty ? " Reconnecting..." : ""
            appendLog("Lost connection to the multiworld server: \(error.localizedDescription)\(hint)")
            delegate?.contextDidReceiveError(self, title: "Connection Lost", message: error.localizedDescription)
        } else {
            appendLog("Disconnected from multiworld server.")
        }

        if !disconnectedIntentionally, !serverAddress.isEmpty, wasJoined {
            scheduleReconnect()
        }
    }

    private func scheduleReconnect() {
        reconnectTask?.cancel()
        let delay = currentReconnectDelay
        currentReconnectDelay = min(currentReconnectDelay * 2, 120)
        appendLog("Automatically reconnecting in \(delay) seconds")
        reconnectTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000_000)
            guard !Task.isCancelled, !disconnectedIntentionally else { return }
            await connectAsync(address: serverAddress)
        }
    }

    private func startKeepAlive() {
        keepAliveTask?.cancel()
        keepAliveTask = Task {
            var elapsed = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let slot, isConnected else { continue }
                elapsed += 1
                if elapsed > 100 {
                    await sendMessages([["cmd": "Bounce", "slots": [slot]]])
                    elapsed = 0
                }
            }
        }
    }
}
