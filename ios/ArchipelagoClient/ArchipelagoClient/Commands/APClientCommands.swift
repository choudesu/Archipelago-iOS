import Foundation

@MainActor
final class APClientCommands {
    private unowned let context: APContext

    init(context: APContext) {
        self.context = context
    }

    func process(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        if trimmed.hasPrefix("/") {
            return processClientCommand(trimmed)
        }

        context.sendSay(trimmed)
        return true
    }

    func helpText() -> String {
        """
        /connect [address] - Connect to a MultiWorld Server
        /disconnect - Disconnect from a MultiWorld Server
        /received - List all received items
        /missing [filter] - List missing location checks
        /items - List all item names for the current game
        /locations - List all location names for the current game
        /ready - Send ready status to server
        /exit - Disconnect and close client session
        """
    }

    private func processClientCommand(_ raw: String) -> Bool {
        let parts = splitCommand(raw)
        guard let command = parts.first?.dropFirst().lowercased() else { return false }
        let args = parts.dropFirst()

        switch command {
        case "connect":
            let address = args.joined(separator: " ")
            if !address.isEmpty {
                context.serverAddress = address
                context.username = nil
                context.password = nil
            } else if context.serverAddress.isEmpty {
                output("Please specify an address.")
                return false
            }
            context.connect(address: address.isEmpty ? nil : address)
            return true
        case "disconnect":
            context.disconnect()
            return true
        case "received":
            output("\(context.itemsReceived.count) received items, sorted by time:")
            for item in context.itemsReceived {
                let itemName = context.nameLookup.lookupItemInSlot(item.item, slot: item.player, slotInfo: context.slotInfo)
                let locationName = context.nameLookup.lookupLocationInSlot(item.location, slot: item.player, slotInfo: context.slotInfo)
                let sender = context.playerNames[item.player] ?? "Player \(item.player)"
                output("\(itemName) from \(locationName) by \(sender)")
            }
            return true
        case "missing":
            let filterText = args.joined(separator: " ")
            guard !context.game.isEmpty else {
                output("No game set, cannot determine missing checks.")
                return false
            }
            var count = 0
            var checkedCount = 0
            for (locationID, location) in context.nameLookup.allLocationEntries(for: context.game) {
                if !filterText.isEmpty, !location.localizedCaseInsensitiveContains(filterText) {
                    continue
                }
                if locationID < 0 { continue }
                if context.locationsChecked.contains(locationID) { continue }
                if context.missingLocations.contains(locationID) {
                    output("Missing: \(location)")
                    count += 1
                } else if context.checkedLocations.contains(locationID) {
                    output("Checked: \(location)")
                    count += 1
                    checkedCount += 1
                }
            }

            if count > 0 {
                if checkedCount > 0 {
                    output("Found \(count) missing location checks. \(checkedCount) location checks previously visited.")
                } else {
                    output("Found \(count) missing location checks.")
                }
            } else {
                output("No missing location checks found.")
            }
            return true
        case "items":
            return outputDataPackagePart(name: "Item Names", values: context.nameLookup.itemNames(for: context.game))
        case "locations":
            return outputDataPackagePart(name: "Location Names", values: context.nameLookup.locationNames(for: context.game))
        case "ready":
            context.ready.toggle()
            let status: ClientStatus = context.ready ? .ready : .connected
            output(context.ready ? "Readied up." : "Unreadied.")
            Task {
                await context.sendMessages([["cmd": "StatusUpdate", "status": status.rawValue]])
            }
            return true
        case "help":
            output(helpText())
            return true
        case "exit":
            context.disconnect()
            return true
        default:
            output("Unknown command /\(command). Use /help for available commands.")
            return false
        }
    }

    private func outputDataPackagePart(name: String, values: [String]) -> Bool {
        guard !context.game.isEmpty else {
            output("No game set, cannot determine \(name).")
            return false
        }
        output("\(name) for \(context.game)")
        for value in values.sorted() {
            output(value)
        }
        return true
    }

    private func output(_ text: String) {
        context.appendLog(text)
    }

    private func splitCommand(_ raw: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false
        for char in raw {
            if char == "\"" {
                inQuotes.toggle()
                continue
            }
            if char == " " && !inQuotes {
                if !current.isEmpty {
                    result.append(current)
                    current = ""
                }
            } else {
                current.append(char)
            }
        }
        if !current.isEmpty {
            result.append(current)
        }
        return result
    }
}
