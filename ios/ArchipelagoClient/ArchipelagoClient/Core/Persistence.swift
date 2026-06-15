import Foundation

enum Persistence {
    private static let defaults = UserDefaults.standard

    static let notificationsEnabledKey = "ap.client.notifications.enabled"
    static let activityAlertsEnabledKey = "ap.client.activityAlerts.enabled"
    static let backgroundSyncEnabledKey = "ap.client.backgroundSync.enabled"
    static let debugModeEnabledKey = "ap.client.debugMode.enabled"
    static let connectionBookmarkChipsEnabledKey = "ap.client.connectionBookmarkChips.enabled"

    private enum Keys {
        static let clientUUID = "ap.client.uuid"
        static let lastServerAddress = "ap.client.lastServerAddress"
        static let lastSlotName = "ap.client.lastSlotName"
        static let deathLinkEnabled = "ap.client.deathLinkEnabled"
        static let notificationsEnabled = notificationsEnabledKey
        static let activityAlertsEnabled = activityAlertsEnabledKey
        static let backgroundSyncEnabled = backgroundSyncEnabledKey
        static let debugModeEnabled = debugModeEnabledKey
        static let connectionBookmarkChipsEnabled = connectionBookmarkChipsEnabledKey
        static let lastActivitySnapshot = "ap.client.lastActivitySnapshot"
        static let backgroundSessionPassword = "ap.client.backgroundSession.password"
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

    static var activityAlertsEnabled: Bool {
        get {
            if defaults.object(forKey: Keys.activityAlertsEnabled) == nil {
                return true
            }
            return defaults.bool(forKey: Keys.activityAlertsEnabled)
        }
        set { defaults.set(newValue, forKey: Keys.activityAlertsEnabled) }
    }

    static var backgroundSyncEnabled: Bool {
        get {
            if defaults.object(forKey: Keys.backgroundSyncEnabled) == nil {
                return true
            }
            return defaults.bool(forKey: Keys.backgroundSyncEnabled)
        }
        set { defaults.set(newValue, forKey: Keys.backgroundSyncEnabled) }
    }

    static var debugModeEnabled: Bool {
        get { defaults.bool(forKey: Keys.debugModeEnabled) }
        set { defaults.set(newValue, forKey: Keys.debugModeEnabled) }
    }

    static var backgroundSessionPassword: String? {
        get { defaults.string(forKey: Keys.backgroundSessionPassword) }
        set {
            if let newValue, !newValue.isEmpty {
                defaults.set(newValue, forKey: Keys.backgroundSessionPassword)
            } else {
                defaults.removeObject(forKey: Keys.backgroundSessionPassword)
            }
        }
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

    static func loadActivitySnapshot() -> ActivitySnapshot {
        guard let data = defaults.data(forKey: Keys.lastActivitySnapshot),
              let snapshot = try? JSONDecoder().decode(ActivitySnapshot.self, from: data) else {
            return .empty
        }
        return snapshot
    }

    static func saveActivitySnapshot(_ snapshot: ActivitySnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: Keys.lastActivitySnapshot)
    }

    static func saveBackgroundSessionCredentials(serverAddress: String, slotName: String, password: String?) {
        lastServerAddress = serverAddress
        lastSlotName = slotName
        backgroundSessionPassword = password
    }

    static var hasBackgroundSessionCredentials: Bool {
        !lastServerAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !lastSlotName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
