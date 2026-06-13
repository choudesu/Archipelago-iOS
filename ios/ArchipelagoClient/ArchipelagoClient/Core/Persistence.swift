import Foundation

enum Persistence {
    private static let defaults = UserDefaults.standard

    static let notificationsEnabledKey = "ap.client.notifications.enabled"
    static let notificationChatEnabledKey = "ap.client.notifications.chat"
    static let notificationItemsEnabledKey = "ap.client.notifications.items"
    static let notificationForegroundEnabledKey = "ap.client.notifications.foreground"

    private enum Keys {
        static let clientUUID = "ap.client.uuid"
        static let lastServerAddress = "ap.client.lastServerAddress"
        static let deathLinkEnabled = "ap.client.deathLinkEnabled"
        static let notificationsEnabled = notificationsEnabledKey
        static let notificationChatEnabled = notificationChatEnabledKey
        static let notificationItemsEnabled = notificationItemsEnabledKey
        static let notificationForegroundEnabled = notificationForegroundEnabledKey
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

    static var deathLinkEnabled: Bool {
        get { defaults.bool(forKey: Keys.deathLinkEnabled) }
        set { defaults.set(newValue, forKey: Keys.deathLinkEnabled) }
    }

    static var notificationsEnabled: Bool {
        get { defaults.bool(forKey: Keys.notificationsEnabled) }
        set { defaults.set(newValue, forKey: Keys.notificationsEnabled) }
    }

    static var notificationChatEnabled: Bool {
        get {
            if defaults.object(forKey: Keys.notificationChatEnabled) == nil {
                return true
            }
            return defaults.bool(forKey: Keys.notificationChatEnabled)
        }
        set { defaults.set(newValue, forKey: Keys.notificationChatEnabled) }
    }

    static var notificationItemsEnabled: Bool {
        get {
            if defaults.object(forKey: Keys.notificationItemsEnabled) == nil {
                return true
            }
            return defaults.bool(forKey: Keys.notificationItemsEnabled)
        }
        set { defaults.set(newValue, forKey: Keys.notificationItemsEnabled) }
    }

    static var notificationForegroundEnabled: Bool {
        get { defaults.bool(forKey: Keys.notificationForegroundEnabled) }
        set { defaults.set(newValue, forKey: Keys.notificationForegroundEnabled) }
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
