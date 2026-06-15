import Foundation

struct ConnectionSession: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var label: String
    var serverAddress: String
    var slotName: String
    let clientUUID: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        label: String,
        serverAddress: String = "",
        slotName: String = "",
        clientUUID: String = UUID().uuidString,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.label = label
        self.serverAddress = serverAddress
        self.slotName = slotName
        self.clientUUID = clientUUID
        self.createdAt = createdAt
    }

    var displaySubtitle: String {
        let server = serverAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let slot = slotName.trimmingCharacters(in: .whitespacesAndNewlines)
        switch (slot.isEmpty, server.isEmpty) {
        case (true, true): return "Not configured"
        case (false, true): return slot
        case (true, false): return server
        case (false, false): return "\(slot) @ \(server)"
        }
    }
}
