import Foundation

@MainActor
final class APTrackerBridge {
    let trackerState = TrackerState()
    private weak var context: APContext?
    private let packStore: PopTrackerPackStore

    init(context: APContext, packStore: PopTrackerPackStore = .shared) {
        self.context = context
        self.packStore = packStore
    }

    func handleConnect() {
        guard let pack = packStore.loadedPack, let context else { return }
        trackerState.reset(for: pack)
        trackerState.applyCheckedLocations(context.checkedLocations, pack: pack)
        for item in context.itemsReceived {
            trackerState.applyReceivedItem(item.item, pack: pack)
        }
        packStore.validateGameMatch(sessionGame: context.activeGameName)
    }

    func handleSlotData(_ slotData: [String: Any]) {
        _ = slotData
    }

    func handleCheckedLocations(_ locationIDs: Set<Int>) {
        guard let pack = packStore.loadedPack else { return }
        trackerState.applyCheckedLocations(locationIDs, pack: pack)
    }

    func handleReceivedItems(_ items: [NetworkItem]) {
        guard let pack = packStore.loadedPack else { return }
        for item in items {
            trackerState.applyReceivedItem(item.item, pack: pack)
        }
    }

    func handleManualCheck(sectionPath: String) async {
        guard let context, let pack = packStore.loadedPack, pack.supportsManualChecks else { return }
        guard let locationID = pack.apLocationID(forSectionPath: sectionPath) else { return }
        _ = await context.checkLocations([locationID])
    }
}
