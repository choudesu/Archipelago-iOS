import SwiftUI

struct TrackerPackPickerView: View {
    @ObservedObject var viewModel: AppViewModel
    @Binding var requestImport: Bool

    var body: some View {
        Section("PopTracker Packs") {
                Button("Import Pack (.zip or folder)") {
                requestImport = true
            }

            if viewModel.packStore.installedPacks.isEmpty {
                Text("No packs installed. Import a PopTracker pack zip to enable map tracking.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.packStore.installedPacks) { pack in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pack.name)
                                .font(.body)
                            Text(pack.gameName.isEmpty ? pack.packageUID : pack.gameName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if viewModel.packStore.loadedPack?.install.packageUID == pack.packageUID {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectPack(pack.packageUID)
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            removePack(pack.packageUID)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }

                if viewModel.packStore.loadedPack != nil {
                    Button("Unload Active Pack", role: .destructive) {
                        unloadPack()
                    }
                }
            }
        }
    }

    private func selectPack(_ uid: String) {
        do {
            try viewModel.setActivePopTrackerPack(uid: uid)
            if Persistence.clientMode != .tracker {
                viewModel.setClientMode(.tracker)
            }
        } catch {
            viewModel.presentError("Pack Error", error.localizedDescription)
        }
    }

    private func unloadPack() {
        do {
            try viewModel.setActivePopTrackerPack(uid: nil)
        } catch {
            viewModel.presentError("Pack Error", error.localizedDescription)
        }
    }

    private func removePack(_ uid: String) {
        do {
            try viewModel.removePopTrackerPack(uid: uid)
        } catch {
            viewModel.presentError("Pack Error", error.localizedDescription)
        }
    }
}
