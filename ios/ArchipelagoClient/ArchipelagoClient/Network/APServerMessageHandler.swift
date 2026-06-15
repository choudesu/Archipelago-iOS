import Foundation

@MainActor
final class APServerMessageHandler {
    unowned let context: APContext

    init(context: APContext) {
        self.context = context
    }

    func handle(_ args: [String: Any]) async {
        guard let cmd = args["cmd"] as? String else { return }

        switch cmd {
        case "RoomInfo":
            await handleRoomInfo(args)
        case "DataPackage":
            if let data = args["data"] as? [String: Any] {
                context.consumeNetworkDataPackage(data)
            }
        case "ConnectionRefused":
            await handleConnectionRefused(args)
        case "Connected":
            await handleConnected(args)
        case "ReceivedItems":
            await handleReceivedItems(args)
        case "LocationInfo":
            handleLocationInfo(args)
        case "RoomUpdate":
            handleRoomUpdate(args)
        case "Print":
            context.onPrint(args)
        case "PrintJSON":
            context.onPrintJSON(args)
        case "InvalidPacket":
            if let type = args["type"], let text = args["text"] {
                context.appendLog("Invalid Packet of \(type): \(text)")
            }
        case "Bounced":
            handleBounced(args)
        case "Retrieved":
            handleRetrieved(args)
        case "SetReply":
            handleSetReply(args)
        default:
            break
        }

        context.onPackage(cmd: cmd, args: args)
    }

    private func handleRoomInfo(_ args: [String: Any]) async {
        if let seed = context.seedName,
           let serverSeed = args["seed_name"] as? String,
           seed != serverSeed {
            context.delegate?.contextDidReceiveError(
                context,
                title: "Error",
                message: "The server is running a different multiworld than your client."
            )
            return
        }

        context.serverVersion = APCodec.parseVersion(args["version"] ?? [:])
        if let generator = args["generator_version"] {
            context.generatorVersion = APCodec.parseVersion(generator)
        }

        context.appendLog("--------------------------------")
        context.appendLog("Room Information:")
        context.appendLog("--------------------------------")
        context.appendLog(
            "Server protocol version: \(context.serverVersion.simpleString), " +
            "generator version: \(context.generatorVersion.simpleString)"
        )

        if args["password"] as? Bool == true {
            context.appendLog("Password required")
        }

        if let permissions = args["permissions"] as? [String: Any] {
            context.updatePermissions(permissions)
        }

        if let hintCost = args["hint_cost"] as? Int {
            context.hintCost = hintCost
        }
        if let checkPoints = args["location_check_points"] as? Int {
            context.checkPoints = checkPoints
        }

        if let hintCost = context.hintCost, let checkPoints = context.checkPoints {
            context.appendLog(
                "A !hint costs \(hintCost)% of your total location count as points " +
                "and you get \(checkPoints) for each location checked."
            )
        }

        let games = Set((args["games"] as? [String]) ?? [])
        let checksums = args["datapackage_checksums"] as? [String: String] ?? [:]
        await context.prepareDataPackage(relevantGames: games, remoteChecksums: checksums)

        let passwordRequired = args["password"] as? Bool ?? false
        await context.serverAuth(passwordRequested: passwordRequired)
    }

    private func handleConnectionRefused(_ args: [String: Any]) async {
        context.markConnectionRefusedHandled()
        let errors = args["errors"] as? [String] ?? []
        context.appendLog("Connection refused: \(errors.isEmpty ? "unknown reason" : errors.joined(separator: ", "))")

        if errors.contains("InvalidSlot") {
            let attempted = context.auth ?? context.username ?? "(empty)"
            context.appendLog("Invalid slot name \"\(attempted)\". Enter the exact slot name from your YAML.")
            context.setSlotName(nil)
            context.delegate?.contextDidReceiveError(
                context,
                title: "Invalid Slot",
                message: "Slot \"\(attempted)\" was not found. Check spelling and try again."
            )
            await context.abortFailedConnect()
        } else if errors.contains("InvalidGame") {
            context.appendLog("Invalid game for this slot. Retrying as text client...")
            await context.sendConnect(extra: ["game": ""])
        } else if errors.contains("IncompatibleVersion") {
            context.delegate?.contextDidReceiveError(
                context,
                title: "Incompatible Version",
                message: "Server rejected protocol version \(context.serverVersion.simpleString). The server may require an exact client version match."
            )
            await context.abortFailedConnect()
        } else if errors.contains("InvalidItemsHandling") {
            context.delegate?.contextDidReceiveError(
                context,
                title: "Invalid Items Handling",
                message: "The item handling flags requested by the client are not supported."
            )
            await context.abortFailedConnect()
        } else if errors.contains("InvalidPassword") {
            context.appendLog("Invalid password")
            context.password = nil
            await context.serverAuth(passwordRequested: true)
        } else if errors.isEmpty {
            context.delegate?.contextDidReceiveError(
                context,
                title: "Connection Refused",
                message: "Connection refused by the multiworld host, no reason provided."
            )
            await context.abortFailedConnect()
        } else {
            context.delegate?.contextDidReceiveError(
                context,
                title: "Connection Refused",
                message: errors.joined(separator: ", ")
            )
            await context.abortFailedConnect()
        }
    }

    private func handleConnected(_ args: [String: Any]) async {
        context.username = context.auth
        context.team = args["team"] as? Int
        context.slot = args["slot"] as? Int
        context.hintPoints = args["hint_points"] as? Int

        context.slotInfo = [0: NetworkSlot(name: "Archipelago", game: "Archipelago", type: SlotType.player.rawValue)]
        if let slotInfo = args["slot_info"] as? [String: Any] {
            for (key, value) in slotInfo {
                guard let slot = Int(key),
                      let networkSlot = NetworkSlot.parseDecodedValue(value) else { continue }
                context.slotInfo[slot] = networkSlot
            }
        }

        context.consumePlayersPackage(args["players"] ?? [])

        if let team = context.team, let slot = context.slot {
            context.storedDataNotificationKeys.insert("_read_hints_\(team)_\(slot)")
        }

        let activeGame: String
        if let slot = context.slot, let info = context.slotInfo[slot] {
            activeGame = info.game
            context.game = info.game
        } else {
            activeGame = ""
            context.game = ""
        }

        if !activeGame.isEmpty {
            context.storedDataNotificationKeys.insert("_read_item_name_groups_\(activeGame)")
            context.storedDataNotificationKeys.insert("_read_location_name_groups_\(activeGame)")
        }

        var messages: [[String: Any]] = []
        context.storedDataNotificationKeys.insert("_read_race_mode")
        if !context.locationsChecked.isEmpty {
            messages.append(["cmd": "LocationChecks", "locations": Array(context.locationsChecked).sorted()])
        }
        if !context.locationsScouted.isEmpty {
            messages.append(["cmd": "LocationScouts", "locations": Array(context.locationsScouted).sorted()])
        }
        if !context.storedDataNotificationKeys.isEmpty {
            let keys = Array(context.storedDataNotificationKeys).sorted()
            messages.append(["cmd": "Get", "keys": keys])
            messages.append(["cmd": "SetNotify", "keys": keys])
        }
        if context.finishedGame {
            messages.append(["cmd": "StatusUpdate", "status": ClientStatus.goal.rawValue])
        }
        if !messages.isEmpty {
            await context.sendMessages(messages)
        }

        if let missing = args["missing_locations"] as? [Int] {
            context.missingLocations = Set(missing)
        }
        if let checked = args["checked_locations"] as? [Int] {
            context.checkedLocations = Set(checked)
        }
        context.serverLocations = context.missingLocations.union(context.checkedLocations)

        context.markConnectSucceeded()
        context.connectionState = .connected
        context.persistBackgroundSessionCredentials()
        context.persistActivitySnapshot()
        context.delegate?.contextDidUpdateConnectionState(context)
        context.delegate?.contextDidUpdateProgress(context)
        context.delegate?.contextDidConnect(context)
        context.appendLog("Joined slot \(context.slot ?? 0) on team \((context.team ?? 0) + 1) as \(context.auth ?? "player")")
        APNotificationService.shared.clearBackgroundDisconnectState()
    }

    private func handleReceivedItems(_ args: [String: Any]) async {
        let startIndex = args["index"] as? Int ?? 0

        if startIndex == 0 {
            context.itemsReceived = []
        } else if startIndex != context.itemsReceived.count {
            var syncMessages: [[String: Any]] = [["cmd": "Sync"]]
            if !context.locationsChecked.isEmpty {
                syncMessages.append([
                    "cmd": "LocationChecks",
                    "locations": Array(context.locationsChecked).sorted()
                ])
            }
            await context.sendMessages(syncMessages)
        }

        if startIndex == context.itemsReceived.count,
           let items = args["items"] as? [Any] {
            let previousCount = context.itemsReceived.count
            for itemValue in items {
                if let item = itemValue as? NetworkItem {
                    context.itemsReceived.append(item)
                } else if let tuple = itemValue as? [Any], tuple.count >= 3 {
                    let item = Int(tuple[0] as? Int ?? 0)
                    let location = Int(tuple[1] as? Int ?? 0)
                    let player = Int(tuple[2] as? Int ?? 0)
                    let flags = tuple.count > 3 ? Int(tuple[3] as? Int ?? 0) : 0
                    context.itemsReceived.append(NetworkItem(item: item, location: location, player: player, flags: flags))
                }
            }
            if let team = context.team, let slot = context.slot {
                Persistence.saveReceivedItemsIndex(context.itemsReceived.count, slot: slot, team: team)
            }
            let newItems = Array(context.itemsReceived.suffix(context.itemsReceived.count - previousCount))
            let isBulkResync = startIndex == 0
            context.notifyNewItems(newItems, isBulkResync: isBulkResync)
        }
    }

    private func handleLocationInfo(_ args: [String: Any]) {
        guard let locations = args["locations"] as? [Any] else { return }
        for value in locations {
            if let item = value as? NetworkItem {
                context.locationsInfo[item.location] = item
            }
        }
    }

    private func handleRoomUpdate(_ args: [String: Any]) {
        if args["players"] != nil {
            context.consumePlayersPackage(args["players"] ?? [])
        }
        if let hintPoints = args["hint_points"] as? Int {
            context.hintPoints = hintPoints
        }
        if let checked = args["checked_locations"] as? [Int] {
            let checkedSet = Set(checked)
            context.checkedLocations.formUnion(checkedSet)
            context.missingLocations.subtract(checkedSet)
            context.delegate?.contextDidUpdateProgress(context)
        }
        if let permissions = args["permissions"] as? [String: Any] {
            context.updatePermissions(permissions)
        }
        if let hintCost = args["hint_cost"] as? Int {
            context.hintCost = hintCost
        }
    }

    private func handleBounced(_ args: [String: Any]) {
        let tags = args["tags"] as? [String] ?? []
        if tags.contains("DeathLink"),
           let data = args["data"] as? [String: Any],
           let time = data["time"] as? TimeInterval,
           context.lastDeathLink != time {
            context.onDeathLink(data)
        }
    }

    private func handleRetrieved(_ args: [String: Any]) {
        guard let keys = args["keys"] as? [String: Any] else { return }
        for (key, value) in keys {
            context.storedData[key] = value
        }
        context.refreshHints()
    }

    private func handleSetReply(_ args: [String: Any]) {
        guard let key = args["key"] as? String else { return }
        context.storedData[key] = args["value"]
        if key.hasPrefix("EnergyLink") {
            context.currentEnergyLinkValue = args["value"] as? Int
        }
        context.refreshHints()
    }
}
