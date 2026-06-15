import Foundation

enum ClientMode: String, CaseIterable, Identifiable {
    case text
    case tracker

    var id: String { rawValue }

    var label: String {
        switch self {
        case .text: return "Text Client"
        case .tracker: return "PopTracker"
        }
    }

    var tags: Set<String> {
        switch self {
        case .text:
            return ["AP", "TextOnly"]
        case .tracker:
            return ["AP", "Tracker", "NoText", "PopTracker"]
        }
    }

    var wantsSlotData: Bool {
        switch self {
        case .text: return false
        case .tracker: return true
        }
    }
}
