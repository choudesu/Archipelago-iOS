import Foundation

@MainActor
final class ConnectionSessionManager: ObservableObject {
    @Published private(set) var sessions: [ConnectionSession] = []
    @Published private(set) var activeSessionID: UUID
    @Published private(set) var primarySessionID: UUID

    private(set) var contexts: [UUID: APContext] = [:]

    var activeContext: APContext {
        guard let context = contexts[activeSessionID] else {
            fatalError("Missing context for active session")
        }
        return context
    }

    var primaryContext: APContext {
        guard let context = contexts[primarySessionID] else {
            return activeContext
        }
        return context
    }

    init() {
        let loaded = Persistence.loadConnectionSessions()
        let resolvedSessions: [ConnectionSession]
        let resolvedActive: UUID
        let resolvedPrimary: UUID
        let shouldSave: Bool

        if loaded.isEmpty {
            let migrated = Self.migrateLegacySession()
            resolvedSessions = [migrated]
            resolvedActive = migrated.id
            resolvedPrimary = migrated.id
            shouldSave = true
        } else {
            resolvedSessions = loaded
            let activeCandidate = Persistence.activeConnectionSessionID ?? loaded[0].id
            resolvedActive = loaded.contains(where: { $0.id == activeCandidate })
                ? activeCandidate
                : loaded[0].id
            let primaryCandidate = Persistence.primaryConnectionSessionID ?? resolvedActive
            resolvedPrimary = loaded.contains(where: { $0.id == primaryCandidate })
                ? primaryCandidate
                : resolvedActive
            shouldSave = false
        }

        sessions = resolvedSessions
        activeSessionID = resolvedActive
        primarySessionID = resolvedPrimary
        if shouldSave {
            saveSessions()
        }
        rebuildContexts()
    }

    func context(for sessionID: UUID) -> APContext? {
        contexts[sessionID]
    }

    func session(for id: UUID) -> ConnectionSession? {
        sessions.first { $0.id == id }
    }

    @discardableResult
    func addSession(label: String? = nil) -> ConnectionSession {
        let index = sessions.count + 1
        let session = ConnectionSession(label: label ?? "Slot \(index)")
        sessions.append(session)
        let context = makeContext(for: session)
        contexts[session.id] = context
        saveSessions()
        return session
    }

    func removeSession(id: UUID) {
        guard sessions.count > 1 else { return }
        contexts[id]?.disconnect()
        contexts[id] = nil
        sessions.removeAll { $0.id == id }
        if activeSessionID == id {
            activeSessionID = sessions[0].id
            Persistence.activeConnectionSessionID = activeSessionID
        }
        if primarySessionID == id {
            primarySessionID = sessions[0].id
            Persistence.primaryConnectionSessionID = primarySessionID
        }
        saveSessions()
    }

    func setActiveSession(id: UUID) {
        guard sessions.contains(where: { $0.id == id }) else { return }
        activeSessionID = id
        Persistence.activeConnectionSessionID = id
    }

    func setPrimarySession(id: UUID) {
        guard sessions.contains(where: { $0.id == id }) else { return }
        primarySessionID = id
        Persistence.primaryConnectionSessionID = id
        syncPrimaryBackgroundCredentials()
    }

    func connect(sessionID: UUID? = nil) {
        let id = sessionID ?? activeSessionID
        guard let context = contexts[id] else { return }
        setActiveSession(id: id)
        context.connect()
    }

    func disconnect(sessionID: UUID? = nil) {
        let id = sessionID ?? activeSessionID
        contexts[id]?.disconnect()
    }

    func connectAll() {
        for session in sessions {
            contexts[session.id]?.connect()
        }
    }

    func disconnectAll() {
        for context in contexts.values {
            context.disconnect()
        }
    }

    func applySession(_ session: ConnectionSession, to context: APContext) {
        context.serverAddress = session.serverAddress
        context.displayAddress = session.serverAddress
        context.setSlotName(session.slotName.isEmpty ? nil : session.slotName)
    }

    func syncSessionMetadata(from context: APContext) {
        guard let index = sessions.firstIndex(where: { $0.id == context.sessionID }) else { return }
        var session = sessions[index]
        let address = context.displayAddress.isEmpty ? context.serverAddress : context.displayAddress
        session.serverAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        session.slotName = context.slotName
        sessions[index] = session
        saveSessions()
        if context.sessionID == primarySessionID {
            syncPrimaryBackgroundCredentials(from: context)
        }
        if context.sessionID == activeSessionID {
            Persistence.lastServerAddress = session.serverAddress
            Persistence.lastSlotName = session.slotName
        }
    }

    func applyConnectedIdentity(from context: APContext) {
        guard let index = sessions.firstIndex(where: { $0.id == context.sessionID }) else { return }
        var session = sessions[index]
        let address = context.displayAddress.isEmpty ? context.serverAddress : context.displayAddress
        session.serverAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        session.slotName = context.slotName
        let connectedName = context.slotName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !connectedName.isEmpty {
            session.label = connectedName
        }
        sessions[index] = session
        saveSessions()
        if context.sessionID == primarySessionID {
            syncPrimaryBackgroundCredentials(from: context)
        }
        if context.sessionID == activeSessionID {
            Persistence.lastServerAddress = session.serverAddress
            Persistence.lastSlotName = session.slotName
        }
    }

    func syncPrimaryBackgroundCredentials(from context: APContext? = nil) {
        let context = context ?? primaryContext
        let address = context.displayAddress.isEmpty ? context.serverAddress : context.displayAddress
        Persistence.saveBackgroundSessionCredentials(
            serverAddress: address,
            slotName: context.slotName,
            password: context.password
        )
    }

    func wireContext(
        _ context: APContext,
        delegate: APContextDelegate?,
        activityRouter: ActivityNotificationRouter?,
        commandProcessor: APClientCommands?
    ) {
        context.delegate = delegate
        context.activityRouter = activityRouter
        context.commandProcessor = commandProcessor
        context.onMetadataChanged = { [weak self, weak context] in
            guard let self, let context else { return }
            self.syncSessionMetadata(from: context)
        }
    }

    func reloadContextConfiguration(mode: ClientMode, trackerGame: String) {
        for context in contexts.values {
            context.applyClientMode(mode)
            context.trackerConnectGame = trackerGame
            if Persistence.deathLinkEnabled, mode == .text {
                context.tags.insert("DeathLink")
            } else {
                context.tags.remove("DeathLink")
            }
        }
    }

    private func rebuildContexts() {
        contexts.removeAll()
        for session in sessions {
            contexts[session.id] = makeContext(for: session)
        }
    }

    private func makeContext(for session: ConnectionSession) -> APContext {
        APContext(
            sessionID: session.id,
            clientUUID: session.clientUUID,
            serverAddress: session.serverAddress,
            slotName: session.slotName
        )
    }

    private func saveSessions() {
        Persistence.saveConnectionSessions(sessions)
        Persistence.activeConnectionSessionID = activeSessionID
        Persistence.primaryConnectionSessionID = primarySessionID
    }

    private static func migrateLegacySession() -> ConnectionSession {
        ConnectionSession(
            label: "Slot 1",
            serverAddress: Persistence.lastServerAddress,
            slotName: Persistence.lastSlotName,
            clientUUID: Persistence.clientUUID
        )
    }
}
