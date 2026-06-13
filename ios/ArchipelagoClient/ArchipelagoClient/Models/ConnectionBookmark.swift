import Foundation

struct ConnectionBookmark: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    var serverAddress: String
    var slotName: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        serverAddress: String,
        slotName: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.serverAddress = serverAddress
        self.slotName = slotName
        self.createdAt = createdAt
    }

    var subtitle: String {
        let host = serverAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let slot = slotName.trimmingCharacters(in: .whitespacesAndNewlines)
        if slot.isEmpty {
            return host
        }
        return "\(slot) @ \(host)"
    }
}
