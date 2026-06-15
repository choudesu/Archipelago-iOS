import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct TrackerMapView: View {
    let pack: PopTrackerLoadedPack
    @ObservedObject var trackerState: TrackerState
    let checkedLocationIDs: Set<Int>
    var onSectionTap: (String) -> Void

    @State private var selectedMapName: String

    private var displayableMaps: [PopTrackerMapDefinition] {
        pack.displayableMaps
    }

    init(
        pack: PopTrackerLoadedPack,
        trackerState: TrackerState,
        checkedLocationIDs: Set<Int>,
        onSectionTap: @escaping (String) -> Void
    ) {
        self.pack = pack
        self.trackerState = trackerState
        self.checkedLocationIDs = checkedLocationIDs
        self.onSectionTap = onSectionTap
        _selectedMapName = State(initialValue: pack.displayableMaps.first?.name ?? "")
    }

    var body: some View {
        VStack(spacing: 8) {
            if displayableMaps.count > 1 {
                Picker("Map", selection: $selectedMapName) {
                    ForEach(displayableMaps) { map in
                        Text(map.name).tag(map.name)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
            }

            if let map = displayableMaps.first(where: { $0.name == selectedMapName }) {
                ScrollView([.horizontal, .vertical]) {
                    ZStack(alignment: .topLeading) {
                        mapImage(for: map)
                            .resizable()
                            .interpolation(.none)
                            .scaledToFit()
                            .frame(minWidth: 320, minHeight: 240)

                        ForEach(currentMarkers(for: map)) { marker in
                            Button {
                                onSectionTap(marker.id)
                            } label: {
                                Circle()
                                    .fill(marker.checked ? Color.green.opacity(0.85) : Color.red.opacity(0.85))
                                    .frame(width: markerSize(for: map), height: markerSize(for: map))
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white, lineWidth: 2)
                                    )
                            }
                            .position(
                                x: marker.x,
                                y: marker.y
                            )
                        }
                    }
                }
            } else {
                ContentUnavailableView("No Maps", systemImage: "map", description: Text("This pack does not define any maps."))
            }
        }
        .onChange(of: pack.install.packageUID) { _, _ in
            selectedMapName = displayableMaps.first?.name ?? ""
        }
        .onChange(of: displayableMaps.map(\.name)) { _, names in
            if !names.contains(selectedMapName) {
                selectedMapName = names.first ?? ""
            }
        }
    }

    private func currentMarkers(for map: PopTrackerMapDefinition) -> [PopTrackerSectionMarker] {
        PopTrackerPackLoader.sectionMarkers(
            for: pack,
            mapName: map.name,
            checkedSectionPaths: trackerState.checkedSectionPaths,
            checkedLocationIDs: checkedLocationIDs
        )
    }

    private func markerSize(for map: PopTrackerMapDefinition) -> CGFloat {
        CGFloat(map.locationSize ?? 24)
    }

    private func mapImage(for map: PopTrackerMapDefinition) -> Image {
        let url = pack.assetURL(for: map.img)
#if canImport(UIKit)
        if let uiImage = UIImage(contentsOfFile: url.path) {
            return Image(uiImage: uiImage)
        }
#endif
        return Image(systemName: "map")
    }
}
