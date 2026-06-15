import SwiftUI

struct TrackerTabView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        List {
            Section("Connection") {
                statusRow("Mode", Persistence.clientMode.label)
                statusRow("Game", viewModel.context.activeGameName.isEmpty ? "—" : viewModel.context.activeGameName)
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

            Section {
                Text("Import a PopTracker pack in Settings to enable map tracking. Tracker mode connects with PopTracker-compatible AP tags and receives slot data from the server.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Tracker")
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
