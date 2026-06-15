import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct TrackerItemsView: View {
    let pack: PopTrackerLoadedPack
    @ObservedObject var trackerState: TrackerState

    private let columns = [GridItem(.adaptive(minimum: 72), spacing: 12)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(pack.items) { item in
                    itemCell(item)
                }
            }
            .padding()
        }
    }

    @ViewBuilder
    private func itemCell(_ item: PopTrackerPackItem) -> some View {
        let primaryCode = item.itemCodes.first ?? item.name
        let active = trackerState.isItemActive(code: primaryCode)
        let count = trackerState.itemCount(code: primaryCode)

        VStack(spacing: 6) {
            itemImage(for: item)
                .resizable()
                .scaledToFit()
                .frame(width: 48, height: 48)
                .opacity(active ? 1 : 0.35)

            Text(item.name)
                .font(.caption2)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            if item.type == "consumable", count > 0 {
                Text("\(count)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(active ? Color.green.opacity(0.12) : Color.secondary.opacity(0.08))
        )
    }

    private func itemImage(for item: PopTrackerPackItem) -> Image {
        guard let path = item.img ?? item.stages?.first?.img else {
            return Image(systemName: "shippingbox")
        }
        let url = pack.assetURL(for: path)
#if canImport(UIKit)
        if let uiImage = UIImage(contentsOfFile: url.path) {
            return Image(uiImage: uiImage)
        }
#endif
        return Image(systemName: "shippingbox")
    }
}
