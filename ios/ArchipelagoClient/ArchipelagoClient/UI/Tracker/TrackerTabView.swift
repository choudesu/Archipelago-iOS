import SwiftUI

struct TrackerTabView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var selectedSection = 0

    var body: some View {
        Group {
            if let pack = viewModel.packStore.loadedPack {
                VStack(spacing: 0) {
                    if let mismatch = viewModel.packStore.gameMismatchMessage {
                        Text(mismatch)
                            .font(.caption)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(8)
                            .background(Color.orange)
                    }

                    Picker("View", selection: $selectedSection) {
                        Text("Map").tag(0)
                        Text("Items").tag(1)
                        Text("Status").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .padding()

                    switch selectedSection {
                    case 0:
                        TrackerMapView(
                            pack: pack,
                            trackerState: viewModel.trackerBridge.trackerState,
                            checkedLocationIDs: viewModel.context.checkedLocations,
                            onSectionTap: { sectionPath in
                                Task {
                                    await viewModel.trackerBridge.handleManualCheck(sectionPath: sectionPath)
                                }
                            }
                        )
                    case 1:
                        TrackerItemsView(
                            pack: pack,
                            trackerState: viewModel.trackerBridge.trackerState
                        )
                    default:
                        trackerStatusList(pack: pack)
                    }
                }
            } else {
                ContentUnavailableView(
                    "No Pack Loaded",
                    systemImage: "map",
                    description: Text("Import a PopTracker pack in Settings to enable map and item tracking.")
                )
            }
        }
        .navigationTitle(viewModel.packStore.loadedPack?.manifest.name ?? "Tracker")
    }

    @ViewBuilder
    private func trackerStatusList(pack: PopTrackerLoadedPack) -> some View {
        List {
            Section("Pack") {
                statusRow("Name", pack.manifest.name)
                statusRow("Game", pack.gameName.isEmpty ? "—" : pack.gameName)
                statusRow("Variant", pack.variantUID)
                statusRow("Manual checks", pack.supportsManualChecks ? "enabled" : "disabled")
            }
            Section("Connection") {
                statusRow("Mode", Persistence.clientMode.label)
                statusRow("Session game", viewModel.context.activeGameName.isEmpty ? "—" : viewModel.context.activeGameName)
                statusRow("Checked", "\(viewModel.context.checkedLocations.count)")
                statusRow("Missing", "\(viewModel.context.missingLocations.count)")
                statusRow("Items received", "\(viewModel.context.itemsReceived.count)")
            }
            if !viewModel.context.slotData.isEmpty {
                Section("Slot Data") {
                    ForEach(viewModel.context.slotData.keys.sorted(), id: \.self) { key in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(key)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(slotDataDescription(viewModel.context.slotData[key]))
                                .font(.caption2)
                        }
                    }
                }
            }
        }
    }

    private func statusRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
        .font(.caption)
    }

    private func slotDataDescription(_ value: Any?) -> String {
        guard let value else { return "nil" }
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        if let bool = value as? Bool { return bool ? "true" : "false" }
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
           let text = String(data: data, encoding: .utf8) {
            return text
        }
        return String(describing: value)
    }
}
