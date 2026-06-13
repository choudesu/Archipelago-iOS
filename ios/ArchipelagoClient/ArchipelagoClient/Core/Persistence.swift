import Foundation

enum Persistence {
    private static let defaults = UserDefaults.standard

    static let notificationsEnabledKey = "ap.client.notifications.enabled"

    private enum Keys {
        static let clientUUID = "ap.client.uuid"
        static let lastServerAddress = "ap.client.lastServerAddress"
        static let lastSlotName = "ap.client.lastSlotName"
        static let deathLinkEnabled = "ap.client.deathLinkEnabled"
        static let notificationsEnabled = notificationsEnabledKey
    }

    static var clientUUID: String {
        if let existing = defaults.string(forKey: Keys.clientUUID) {
            return existing
        }
        let uuid = UUID().uuidString
        defaults.set(uuid, forKey: Keys.clientUUID)
        return uuid
    }

    static var lastServerAddress: String {
        get { defaults.string(forKey: Keys.lastServerAddress) ?? "" }
        set { defaults.set(newValue, forKey: Keys.lastServerAddress) }
    }

    static var lastSlotName: String {
        get { defaults.string(forKey: Keys.lastSlotName) ?? "" }
        set { defaults.set(newValue, forKey: Keys.lastSlotName) }
    }

    static var deathLinkEnabled: Bool {
        get { defaults.bool(forKey: Keys.deathLinkEnabled) }
        set { defaults.set(newValue, forKey: Keys.deathLinkEnabled) }
    }

    static var notificationsEnabled: Bool {
        get { defaults.bool(forKey: Keys.notificationsEnabled) }
        set { defaults.set(newValue, forKey: Keys.notificationsEnabled) }
    }

    static func receivedItemsIndexKey(slot: Int, team: Int) -> String {
        "ap.receivedItems.\(team).\(slot)"
    }

    static func loadReceivedItemsIndex(slot: Int, team: Int) -> Int {
        defaults.integer(forKey: receivedItemsIndexKey(slot: slot, team: team))
    }

    static func saveReceivedItemsIndex(_ index: Int, slot: Int, team: Int) {
        defaults.set(index, forKey: receivedItemsIndexKey(slot: slot, team: team))
    }
}
