import Foundation

@MainActor
protocol APContextDelegate: AnyObject {
    func contextDidUpdateConnectionState(_ context: APContext)
    func contextDidReceiveLog(_ context: APContext, entry: ChatLogEntry)
    func contextDidReceiveError(_ context: APContext, title: String, message: String)
    func contextNeedsUserInput(_ context: APContext, prompt: String) async -> String
    func contextDidUpdateHints(_ context: APContext)
    func contextDidUpdateProgress(_ context: APContext)
    func contextDidConnect(_ context: APContext)
    func contextDidReceiveSlotData(_ context: APContext, slotData: [String: Any])
    func contextDidUpdateCheckedLocations(_ context: APContext, locationIDs: Set<Int>)
    func contextDidReceiveItems(_ context: APContext, items: [NetworkItem])
}

@MainActor
final class APContext: ObservableObject {
    weak var delegate: APContextDelegate?

    let sessionID: UUID
    var clientUUID: String
    var onMetadataChanged: (() -> Void)?

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

    var tags: Set<String> = ClientMode.text.tags
    var itemsHandling = 0b111
    var wantSlotData = false
    var clientMode: ClientMode = .text
    var trackerConnectGame: String = ""
    var slotData: [String: Any] = [:]

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

    weak var activityRouter: ActivityNotificationRouter?
    var seenHintKeys: Set<String> = []
    private var hintsActivitySeeded = false

    @Published private(set) var chatLog: [ChatLogEntry] = []
    @Published private(set) var hints: [HintEntry] = []
    @Published var awaitingInputPrompt: String?
    @Published private(set) var dataPackageStatus: DataPackageStatusInfo?

    private var webSocket: APWebSocketSession?
    private var messageHandler: APServerMessageHandler?
    private var keepAliveTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var connectionWorkTask: Task<Void, Never>?
    private var dataPackageStatusTask: Task<Void, Never>?
    private var connectionGeneration = 0
    private var awaitingConnectResponse = false
    private var connectionRefusedHandled = false
    private var disconnectedIntentionally = false
    private var currentReconnectDelay = 30
    private let startingReconnectDelay = 30
    private let maxReconnectDelay = 300
    private var inputContinuation: CheckedContinuation<String, Never>?

    var commandProcessor: APClientCommands?

    var isConnected: Bool { connectionState == .connected && webSocket?.isOpen == true }
    var suggestedAddress: String { serverAddress }

    var totalLocations: Int? {
        if checkedLocations.isEmpty && missingLocations.isEmpty { return nil }
        return checkedLocations.union(missingLocations).count
    }

    var progressValue: Double {
        guard let total = totalLocations, total > 0 else { return 0 }
        return Double(checkedLocations.count) / Double(total)
    }

    init(
        sessionID: UUID = UUID(),
        clientUUID: String = UUID().uuidString,
        serverAddress: String = "",
        slotName: String = "",
        password: String? = nil
    ) {
        self.sessionID = sessionID
        self.clientUUID = clientUUID
        self.serverAddress = serverAddress
        self.password = password
        self.messageHandler = APServerMessageHandler(context: self)
        displayAddress = serverAddress
        let savedSlot = slotName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !savedSlot.isEmpty {
            auth = savedSlot
            username = savedSlot
        }
        applyClientMode(Persistence.clientMode)
        trackerConnectGame = Persistence.trackerConnectGame
    }

    /// Ephemeral context for background sync using legacy global credentials.
    convenience init(legacyEphemeralServerAddress serverAddress: String, password: String?) {
        self.init(
            sessionID: UUID(),
            clientUUID: Persistence.clientUUID,
            serverAddress: serverAddress,
            slotName: Persistence.lastSlotName,
            password: password
        )
    }

    func applyClientMode(_ mode: ClientMode) {
        clientMode = mode
        tags = mode.tags
        wantSlotData = mode.wantsSlotData
    }

    func restorePendingLocationSync() {
        guard let team, let slot else { return }
        locationsChecked.formUnion(Persistence.loadPendingLocationChecks(slot: slot, team: team))
        locationsScouted.formUnion(Persistence.loadPendingLocationScouts(slot: slot, team: team))
    }

    func persistPendingLocationSync() {
        guard let team, let slot else { return }
        Persistence.savePendingLocationChecks(locationsChecked, slot: slot, team: team)
        Persistence.savePendingLocationScouts(locationsScouted, slot: slot, team: team)
    }

    @discardableResult
    func checkLocations(_ ids: Set<Int>) async -> Set<Int> {
        let newChecks = ids.intersection(missingLocations)
        guard !newChecks.isEmpty else { return [] }
        locationsChecked.formUnion(newChecks)
        persistPendingLocationSync()
        await sendMessages([
            ["cmd": "LocationChecks", "locations": Array(newChecks).sorted()]
        ])
        return newChecks
    }

    @discardableResult
    func scoutLocations(_ ids: Set<Int>, asHint: Bool) async -> Set<Int> {
        let newScouts = ids.intersection(missingLocations)
        guard !newScouts.isEmpty else { return [] }
        locationsScouted.formUnion(newScouts)
        persistPendingLocationSync()
        await sendMessages([
            [
                "cmd": "LocationScouts",
                "locations": Array(newScouts).sorted(),
                "create_as_hint": asHint
            ]
        ])
        return newScouts
    }

    func mergeCheckedLocations(_ locationIDs: Set<Int>) {
        guard !locationIDs.isEmpty else { return }
        checkedLocations.formUnion(locationIDs)
        missingLocations.subtract(locationIDs)
        locationsChecked.subtract(locationIDs)
        persistPendingLocationSync()
        delegate?.contextDidUpdateCheckedLocations(self, locationIDs: locationIDs)
    }

    func setSlotName(_ name: String?) {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            auth = nil
            username = nil
        } else {
            auth = trimmed
            username = trimmed
        }
        onMetadataChanged?()
    }

    var slotName: String {
        (auth ?? username ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var notificationSessionLabel: String? {
        let name = slotName
        return name.isEmpty ? nil : name
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
        disconnectedIntentionally = false
        reconnectTask?.cancel()
        reconnectTask = nil
        connectionWorkTask?.cancel()
        connectionWorkTask = Task { @MainActor in
            await connectAsync(address: address, isAutoReconnect: false)
        }
    }

    func disconnect(allowAutoreconnect: Bool = false) {
        if !allowAutoreconnect {
            disconnectedIntentionally = true
            currentReconnectDelay = startingReconnectDelay
            APNotificationService.shared.clearBackgroundDisconnectState()
            reconnectTask?.cancel()
            reconnectTask = nil
            connectionWorkTask?.cancel()
            connectionWorkTask = nil
        }
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
        guard let status else { return }
        applyLocalHintStatus(location: location, findingPlayer: findingPlayer, status: status)

        let message: [String: Any] = [
            "cmd": "UpdateHint",
            "location": location,
            "player": findingPlayer,
            "status": status.rawValue
        ]
        Task { await sendMessages([message]) }
    }

    func canUpdateHint(_ hint: HintEntry) -> Bool {
        guard isConnected, !hint.found, hint.status != .found else { return false }
        return slotConcernsSelf(hint.receivingPlayer)
    }

    private func applyLocalHintStatus(location: Int, findingPlayer: Int, status: HintStatus) {
        guard let team, let slot else { return }
        let key = "_read_hints_\(team)_\(slot)"

        hints = hints.map { hint in
            guard hint.location == location, hint.findingPlayer == findingPlayer else { return hint }
            var updated = hint
            updated.status = status
            return updated
        }

        guard var raw = storedData[key] as? [[String: Any]] else { return }
        for index in raw.indices {
            let entryLocation = raw[index]["location"] as? Int
            let entryFindingPlayer = raw[index]["finding_player"] as? Int
            if entryLocation == location, entryFindingPlayer == findingPlayer {
                raw[index]["status"] = status.rawValue
                break
            }
        }
        storedData[key] = raw
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
        let previousHints = hints
        let key = "_read_hints_\(team)_\(slot)"
        if let raw = storedData[key] as? [[String: Any]] {
            hints = raw.map { HintEntry(from: $0) }
        } else {
            hints = []
        }

        if !hintsActivitySeeded {
            seedHintActivityKeys()
            hintsActivitySeeded = true
        } else {
            processNewHintsForActivity(previousHints: previousHints)
        }

        objectWillChange.send()
        delegate?.contextDidUpdateHints(self)
    }

    func notifyNewItems(_ items: [NetworkItem], isBulkResync: Bool) {
        if !items.isEmpty {
            delegate?.contextDidReceiveItems(self, items: items)
        }
        guard !isBulkResync, let router = activityRouter else {
            if !isBulkResync {
                persistActivitySnapshot()
            }
            return
        }
        for item in items {
            let event = ActivityNotificationBuilder.itemEvent(
                item: item,
                nameLookup: nameLookup,
                playerNames: playerNames,
                slotInfo: slotInfo,
                sessionLabel: notificationSessionLabel
            )
            router.deliver(event)
        }
        persistActivitySnapshot()
    }

    func persistActivitySnapshot() {
        let snapshot = ActivitySnapshot(
            itemCount: itemsReceived.count,
            seenHintKeys: Array(seenHintKeys).sorted(),
            updatedAt: Date()
        )
        Persistence.saveActivitySnapshot(snapshot, sessionID: sessionID)
    }

    func persistBackgroundSessionCredentials() {
        let address = displayAddress.isEmpty ? serverAddress : displayAddress
        Persistence.saveBackgroundSessionCredentials(
            serverAddress: address,
            slotName: slotName,
            password: password
        )
    }

    private func seedHintActivityKeys() {
        for hint in hints {
            seenHintKeys.insert(ActivityNotificationBuilder.hintKey(for: hint))
        }
        persistActivitySnapshot()
    }

    private func processNewHintsForActivity(previousHints: [HintEntry]) {
        guard let router = activityRouter else { return }
        let previousKeys = Set(previousHints.map(ActivityNotificationBuilder.hintKey(for:)))
        for hint in hints {
            let key = ActivityNotificationBuilder.hintKey(for: hint)
            guard !previousKeys.contains(key), !seenHintKeys.contains(key) else { continue }
            guard ActivityNotificationBuilder.hintInvolvesSelf(
                receivingPlayer: hint.receivingPlayer,
                findingPlayer: hint.findingPlayer,
                slotConcernsSelf: slotConcernsSelf
            ) else { continue }
            seenHintKeys.insert(key)
            router.deliver(ActivityNotificationBuilder.hintEvent(
                hint: hint,
                nameLookup: nameLookup,
                playerNames: playerNames,
                slotInfo: slotInfo,
                sessionLabel: notificationSessionLabel
            ))
        }
        persistActivitySnapshot()
    }

    private func handlePrintJSONActivity(_ args: [String: Any]) {
        guard args["type"] as? String == "Hint",
              let router = activityRouter else { return }

        let receiving = args["receiving"] as? Int ?? 0
        let findingPlayer: Int
        let itemID: Int
        let locationID: Int
        let itemFlags: Int

        if let itemDict = args["item"] as? [String: Any] {
            findingPlayer = itemDict["player"] as? Int ?? 0
            itemID = itemDict["item"] as? Int ?? 0
            locationID = itemDict["location"] as? Int ?? 0
            itemFlags = itemDict["flags"] as? Int ?? 0
        } else if let item = args["item"] as? NetworkItem {
            findingPlayer = item.player
            itemID = item.item
            locationID = item.location
            itemFlags = item.flags
        } else {
            return
        }

        guard ActivityNotificationBuilder.hintInvolvesSelf(
            receivingPlayer: receiving,
            findingPlayer: findingPlayer,
            slotConcernsSelf: slotConcernsSelf
        ) else { return }

        let key = ActivityNotificationBuilder.hintDedupKey(
            findingPlayer: findingPlayer,
            location: locationID,
            item: itemID,
            receivingPlayer: receiving
        )
        guard !seenHintKeys.contains(key) else { return }
        seenHintKeys.insert(key)

        router.deliver(ActivityNotificationBuilder.hintEvent(
            receivingPlayer: receiving,
            findingPlayer: findingPlayer,
            itemID: itemID,
            locationID: locationID,
            itemFlags: itemFlags,
            entrance: "",
            nameLookup: nameLookup,
            playerNames: playerNames,
            slotInfo: slotInfo,
            sessionLabel: notificationSessionLabel
        ))
        persistActivitySnapshot()
    }

    func markConnectionRefusedHandled() {
        connectionRefusedHandled = true
        awaitingConnectResponse = false
    }

    func markConnectSucceeded() {
        awaitingConnectResponse = false
        connectionRefusedHandled = false
    }

    /// Stops a failed join attempt without scheduling auto-reconnect.
    func abortFailedConnect() async {
        reconnectTask?.cancel()
        reconnectTask = nil
        connectionWorkTask?.cancel()
        connectionWorkTask = nil
        awaitingConnectResponse = false
        connectionRefusedHandled = true
        disconnectedIntentionally = true
        currentReconnectDelay = startingReconnectDelay
        APNotificationService.shared.clearBackgroundDisconnectState()
        await disconnectAsync(allowAutoreconnect: false)
    }

    // MARK: - Internal handlers used by APServerMessageHandler

    func resetServerState() {
        slot = nil
        team = nil
        game = ""
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
        seenHintKeys = []
        hintsActivitySeeded = false
        slotData = [:]
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
        var loaded: [String] = []
        var failed: [String] = []
        for (game, gameData) in games {
            if let package = GamesPackage.parse(gameData: gameData) {
                DataPackageCache.shared.store(package: package, game: game)
                nameLookup.updateGame(package, game: game)
                loaded.append(game)
            } else {
                failed.append(game)
            }
        }
        if !loaded.isEmpty && failed.isEmpty {
            setDataPackageStatus(DataPackageStatusInfo(phase: .loaded, games: loaded.sorted()))
        } else if !loaded.isEmpty {
            setDataPackageStatus(
                DataPackageStatusInfo(phase: .loaded, games: (loaded + failed).sorted())
            )
        } else if !failed.isEmpty {
            setDataPackageStatus(DataPackageStatusInfo(phase: .failed, games: failed.sorted()))
        }
    }

    func prepareDataPackage(relevantGames: Set<String>, remoteChecksums: [String: String]) async {
        var games = relevantGames
        games.insert("Archipelago")

        let needed = DataPackageCache.shared.gamesNeedingUpdate(
            relevantGames: games,
            remoteChecksums: remoteChecksums
        )
        syncNameLookup(for: games)

        guard !needed.isEmpty else { return }
        setDataPackageStatus(
            DataPackageStatusInfo(phase: .loading, games: needed.sorted()),
            clearAfter: nil
        )
        let messages = needed.map { ["cmd": "GetDataPackage", "games": [$0]] as [String: Any] }
        await sendMessages(messages)
    }

    func setDataPackageStatus(_ status: DataPackageStatusInfo?, clearAfter seconds: TimeInterval? = 4) {
        dataPackageStatusTask?.cancel()
        dataPackageStatusTask = nil

        var resolved = status
        if var updated = status, let current = dataPackageStatus {
            switch (current.phase, updated.phase) {
            case (.loading, .loading), (.loading, .loaded):
                updated = DataPackageStatusInfo(phase: updated.phase, games: updated.games, id: current.id)
            default:
                break
            }
            resolved = updated
        }

        let statusID = resolved?.id
        dataPackageStatus = resolved
        guard resolved != nil, let seconds else { return }
        dataPackageStatusTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            if dataPackageStatus?.id == statusID {
                dataPackageStatus = nil
            }
        }
    }

    private func clearDataPackageStatus() {
        dataPackageStatusTask?.cancel()
        dataPackageStatusTask = nil
        dataPackageStatus = nil
    }

    private func syncNameLookup(for games: Set<String>) {
        var updated = false
        for game in games {
            guard let package = DataPackageCache.shared.package(for: game) else { continue }
            nameLookup.updateGame(package, game: game)
            updated = true
        }
        if updated {
            objectWillChange.send()
        }
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
        username = name
        onMetadataChanged?()
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
            "uuid": clientUUID,
            "game": clientMode == .tracker ? trackerConnectGame : "",
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
            slotInfo: slotInfo,
            slotConcernsSelf: slotConcernsSelf
        )
        appendLog(renderer.render(parts), parts: parts)
        handlePrintJSONActivity(args)
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
            if let slot, let info = slotInfo[slot] {
                game = info.game
            } else {
                game = ""
            }
        }
    }

    /// Game for the currently joined slot, preferring live slot info over cached state.
    var activeGameName: String {
        if let slot, let info = slotInfo[slot], !info.game.isEmpty {
            return info.game
        }
        return game
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

    private func connectAsync(address: String?, isAutoReconnect: Bool = false) async {
        if isAutoReconnect && disconnectedIntentionally { return }
        if Task.isCancelled { return }

        await disconnectAsync(allowAutoreconnect: true)
        if Task.isCancelled || disconnectedIntentionally { return }

        let target = (address?.isEmpty == false ? address : nil) ?? (serverAddress.isEmpty ? nil : serverAddress)
        guard let target, !target.isEmpty else {
            appendLog("Please connect to an Archipelago server.")
            return
        }

        connectionState = .connecting
        delegate?.contextDidUpdateConnectionState(self)

        do {
            let parsed = try ServerURLParser.parse(target)
            if let user = parsed.username {
                setSlotName(user)
            }
            if let pass = parsed.password { password = pass }
            displayAddress = parsed.displayAddress
            serverAddress = parsed.displayAddress
            Persistence.lastServerAddress = parsed.displayAddress

            let candidates = ServerURLParser.connectionCandidates(parsed)
            var lastError: Error?

            for (index, candidate) in candidates.enumerated() {
                if Task.isCancelled || disconnectedIntentionally { return }

                if index == 0 {
                    appendLog("Connecting to \(candidate.websocketURL.absoluteString)...")
                } else {
                    appendLog("Retrying with \(candidate.websocketURL.absoluteString)...")
                }

                do {
                    try await openWebSocket(parsed: candidate)
                    if Task.isCancelled || disconnectedIntentionally {
                        teardownActiveWebSocket()
                        return
                    }
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
            if Task.isCancelled || disconnectedIntentionally { return }
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
            currentReconnectDelay = startingReconnectDelay
            APNotificationService.shared.clearBackgroundDisconnectState()
            reconnectTask?.cancel()
            reconnectTask = nil
            connectionWorkTask?.cancel()
            connectionWorkTask = nil
        }
        keepAliveTask?.cancel()
        keepAliveTask = nil
        clearDataPackageStatus()
        teardownActiveWebSocket()
        resetServerState()
        connectionState = .disconnected
        delegate?.contextDidUpdateConnectionState(self)
    }

    private static let noisyIncomingCommands: Set<String> = [
        "PrintJSON", "RoomUpdate", "ReceivedItems", "Bounced", "SetReply", "Retrieved", "DataPackage"
    ]

    private func handleIncoming(_ text: String) async {
        do {
            let messages = try APCodec.decode(text)
            for message in messages {
                if let cmd = message["cmd"] as? String,
                   !Self.noisyIncomingCommands.contains(cmd) {
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
            let willReconnect = !disconnectedIntentionally && !serverAddress.isEmpty && wasJoined
            let hint = willReconnect ? " Reconnecting..." : ""
            appendLog("Lost connection to the multiworld server: \(error.localizedDescription)\(hint)")
            if !willReconnect {
                delegate?.contextDidReceiveError(self, title: "Connection Lost", message: error.localizedDescription)
            }
        } else {
            appendLog("Disconnected from multiworld server.")
        }

        if !disconnectedIntentionally, !serverAddress.isEmpty, wasJoined {
            scheduleReconnect()
        }

        APNotificationService.shared.notifyDisconnectedDueToBackground(
            wasJoined: wasJoined,
            intentional: disconnectedIntentionally
        )
    }

    private func scheduleReconnect() {
        guard !disconnectedIntentionally, !serverAddress.isEmpty else { return }

        reconnectTask?.cancel()
        let delay = currentReconnectDelay
        currentReconnectDelay = min(currentReconnectDelay * 2, maxReconnectDelay)
        appendLog("Automatically reconnecting in \(delay) seconds")
        reconnectTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled, !disconnectedIntentionally else { return }
            connectionWorkTask?.cancel()
            connectionWorkTask = Task { @MainActor in
                await connectAsync(address: serverAddress, isAutoReconnect: true)
            }
            await connectionWorkTask?.value
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
