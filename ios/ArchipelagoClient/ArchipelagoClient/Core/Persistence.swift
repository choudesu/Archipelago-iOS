import Foundation

enum Persistence {
    private static let defaults = UserDefaults.standard

    static let notificationsEnabledKey = "ap.client.notifications.enabled"
    static let activityAlertsEnabledKey = "ap.client.activityAlerts.enabled"
    static let backgroundSyncEnabledKey = "ap.client.backgroundSync.enabled"
    static let connectionBookmarkChipsEnabledKey = "ap.client.connectionBookmarkChips.enabled"
    static let clientModeKey = "ap.client.mode"
    static let trackerConnectGameKey = "ap.client.trackerConnectGame"
    static let activePopTrackerPackUIDKey = "ap.client.poptracker.activePackUID"
    static let activePopTrackerVariantUIDKey = "ap.client.poptracker.activeVariantUID"
    static let connectionSessionsKey = "ap.client.connectionSessions"
    static let activeConnectionSessionIDKey = "ap.client.activeConnectionSessionID"
    static let primaryConnectionSessionIDKey = "ap.client.primaryConnectionSessionID"

    private enum Keys {
        static let clientUUID = "ap.client.uuid"
        static let lastServerAddress = "ap.client.lastServerAddress"
        static let lastSlotName = "ap.client.lastSlotName"
        static let deathLinkEnabled = "ap.client.deathLinkEnabled"
        static let notificationsEnabled = notificationsEnabledKey
        static let activityAlertsEnabled = activityAlertsEnabledKey
        static let backgroundSyncEnabled = backgroundSyncEnabledKey
        static let connectionBookmarkChipsEnabled = connectionBookmarkChipsEnabledKey
        static let clientMode = clientModeKey
        static let trackerConnectGame = trackerConnectGameKey
        static let activePopTrackerPackUID = activePopTrackerPackUIDKey
        static let activePopTrackerVariantUID = activePopTrackerVariantUIDKey
        static let connectionSessions = connectionSessionsKey
        static let activeConnectionSessionID = activeConnectionSessionIDKey
        static let primaryConnectionSessionID = primaryConnectionSessionIDKey
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

    static var clientMode: ClientMode {
        get {
            guard let raw = defaults.string(forKey: Keys.clientMode),
                  let mode = ClientMode(rawValue: raw) else {
                return .text
            }
            return mode
        }
        set { defaults.set(newValue.rawValue, forKey: Keys.clientMode) }
    }

    static var trackerConnectGame: String {
        get { defaults.string(forKey: Keys.trackerConnectGame) ?? "" }
        set { defaults.set(newValue, forKey: Keys.trackerConnectGame) }
    }

    static var activePopTrackerPackUID: String? {
        get { defaults.string(forKey: Keys.activePopTrackerPackUID) }
        set {
            if let newValue, !newValue.isEmpty {
                defaults.set(newValue, forKey: Keys.activePopTrackerPackUID)
            } else {
                defaults.removeObject(forKey: Keys.activePopTrackerPackUID)
            }
        }
    }

    static var activePopTrackerVariantUID: String? {
        get { defaults.string(forKey: Keys.activePopTrackerVariantUID) }
        set {
            if let newValue, !newValue.isEmpty {
                defaults.set(newValue, forKey: Keys.activePopTrackerVariantUID)
            } else {
                defaults.removeObject(forKey: Keys.activePopTrackerVariantUID)
            }
        }
    }

    static func pendingLocationChecksKey(slot: Int, team: Int) -> String {
        "ap.pendingLocationChecks.\(team).\(slot)"
    }

    static func pendingLocationScoutsKey(slot: Int, team: Int) -> String {
        "ap.pendingLocationScouts.\(team).\(slot)"
    }

    static func loadPendingLocationChecks(slot: Int, team: Int) -> Set<Int> {
        let values = defaults.array(forKey: pendingLocationChecksKey(slot: slot, team: team)) as? [Int] ?? []
        return Set(values)
    }

    static func savePendingLocationChecks(_ locations: Set<Int>, slot: Int, team: Int) {
        defaults.set(Array(locations).sorted(), forKey: pendingLocationChecksKey(slot: slot, team: team))
    }

    static func loadPendingLocationScouts(slot: Int, team: Int) -> Set<Int> {
        let values = defaults.array(forKey: pendingLocationScoutsKey(slot: slot, team: team)) as? [Int] ?? []
        return Set(values)
    }

    static func savePendingLocationScouts(_ locations: Set<Int>, slot: Int, team: Int) {
        defaults.set(Array(locations).sorted(), forKey: pendingLocationScoutsKey(slot: slot, team: team))
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

    static func loadConnectionSessions() -> [ConnectionSession] {
        guard let data = defaults.data(forKey: Keys.connectionSessions),
              let sessions = try? JSONDecoder().decode([ConnectionSession].self, from: data) else {
            return []
        }
        return sessions
    }

    static func saveConnectionSessions(_ sessions: [ConnectionSession]) {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        defaults.set(data, forKey: Keys.connectionSessions)
    }

    static var activeConnectionSessionID: UUID? {
        get {
            guard let raw = defaults.string(forKey: Keys.activeConnectionSessionID) else { return nil }
            return UUID(uuidString: raw)
        }
        set {
            if let newValue {
                defaults.set(newValue.uuidString, forKey: Keys.activeConnectionSessionID)
            } else {
                defaults.removeObject(forKey: Keys.activeConnectionSessionID)
            }
        }
    }

    static var primaryConnectionSessionID: UUID? {
        get {
            guard let raw = defaults.string(forKey: Keys.primaryConnectionSessionID) else { return nil }
            return UUID(uuidString: raw)
        }
        set {
            if let newValue {
                defaults.set(newValue.uuidString, forKey: Keys.primaryConnectionSessionID)
            } else {
                defaults.removeObject(forKey: Keys.primaryConnectionSessionID)
            }
        }
    }

    static func activitySnapshotKey(sessionID: UUID) -> String {
        "ap.client.activitySnapshot.\(sessionID.uuidString)"
    }

    static func loadActivitySnapshot(sessionID: UUID) -> ActivitySnapshot {
        guard let data = defaults.data(forKey: activitySnapshotKey(sessionID: sessionID)),
              let snapshot = try? JSONDecoder().decode(ActivitySnapshot.self, from: data) else {
            return .empty
        }
        return snapshot
    }

    static func saveActivitySnapshot(_ snapshot: ActivitySnapshot, sessionID: UUID) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: activitySnapshotKey(sessionID: sessionID))
    }
}
