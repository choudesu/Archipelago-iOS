import Foundation

struct TrackerItemState: Equatable {
    var active: Bool = false
    var acquiredCount: Int = 0
    var stageIndex: Int = 0
}

@MainActor
final class TrackerState: ObservableObject {
    @Published private(set) var checkedSectionPaths: Set<String> = []
    @Published private(set) var itemStates: [String: TrackerItemState] = [:]

    func reset(for pack: PopTrackerLoadedPack) {
        checkedSectionPaths = []
        itemStates = [:]
        for item in pack.items {
            for code in item.itemCodes {
                itemStates[code] = TrackerItemState()
            }
        }
        for path in pack.sectionPaths {
            if itemStates[path] == nil {
                itemStates[path] = TrackerItemState()
            }
        }
    }

    func applyCheckedLocations(_ locationIDs: Set<Int>, pack: PopTrackerLoadedPack) {
        for locationID in locationIDs {
            for path in pack.sectionPathByAPLocationID[locationID] ?? [] {
                checkedSectionPaths.insert(path)
            }
        }
    }

    func applyReceivedItem(_ itemID: Int, pack: PopTrackerLoadedPack) {
        guard let codes = pack.itemMapping[itemID] else { return }
        for code in codes {
            if pack.sectionPaths.contains(code) {
                checkedSectionPaths.insert(code)
                continue
            }
            var state = itemStates[code] ?? TrackerItemState()
            if let item = pack.items.first(where: { $0.itemCodes.contains(code) }) {
                switch item.type {
                case "consumable":
                    state.acquiredCount += 1
                    if let max = item.maxQuantity {
                        state.acquiredCount = min(state.acquiredCount, max)
                    }
                    state.active = state.acquiredCount > 0
                case "progressive", "progressive_toggle":
                    state.stageIndex += 1
                    state.active = true
                default:
                    state.active = true
                }
            } else {
                state.active = true
            }
            itemStates[code] = state
        }
    }

    func isItemActive(code: String) -> Bool {
        itemStates[code]?.active == true
    }

    func itemCount(code: String) -> Int {
        itemStates[code]?.acquiredCount ?? 0
    }
}
