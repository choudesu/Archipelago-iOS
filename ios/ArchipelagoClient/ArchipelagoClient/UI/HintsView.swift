import SwiftUI

struct HintsView: View {
    @ObservedObject var context: APContext
    @Environment(\.colorScheme) private var colorScheme
    @State private var hintQuery = ""

    var body: some View {
        VStack(spacing: 0) {
            HintInputView(context: context, query: $hintQuery)

            if context.hints.isEmpty {
                ContentUnavailableView(
                    "No Hints",
                    systemImage: "lightbulb",
                    description: Text("Hints appear here after connecting.")
                )
                .frame(maxHeight: .infinity)
            } else {
                List(context.hints) { hint in
                    HintRowView(
                        hint: hint,
                        canEdit: context.canUpdateHint(hint),
                        itemName: itemName(for: hint),
                        locationName: locationName(for: hint),
                        findingPlayer: playerName(hint.findingPlayer),
                        receivingPlayer: playerName(hint.receivingPlayer),
                        onStatusChange: { status in
                            context.updateHint(
                                location: hint.location,
                                findingPlayer: hint.findingPlayer,
                                status: status
                            )
                        }
                    )
                    .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
                }
                .listStyle(.insetGrouped)
                .scrollDismissesKeyboard(.interactively)
            }
        }
    }

    private func itemName(for hint: HintEntry) -> String {
        context.nameLookup.lookupItemInSlot(hint.item, slot: hint.receivingPlayer, slotInfo: context.slotInfo)
    }

    private func locationName(for hint: HintEntry) -> String {
        context.nameLookup.lookupLocationInSlot(hint.location, slot: hint.findingPlayer, slotInfo: context.slotInfo)
    }

    private func playerName(_ slot: Int) -> String {
        context.playerNames[slot] ?? "Player \(slot)"
    }
}

private struct HintRowView: View {
    @Environment(\.colorScheme) private var colorScheme

    let hint: HintEntry
    let canEdit: Bool
    let itemName: String
    let locationName: String
    let findingPlayer: String
    let receivingPlayer: String
    let onStatusChange: (HintStatus) -> Void

    private var palette: APArchipelagoColors.Palette {
        APArchipelagoColors.palette(for: colorScheme)
    }

    private var isFound: Bool {
        hint.found || hint.status == .found
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            statusControl

            VStack(alignment: .leading, spacing: 6) {
                Text(itemName)
                    .font(.headline)
                    .foregroundStyle(isFound ? .secondary : .primary)

                Label(locationName, systemImage: "mappin.and.ellipse")
                    .font(.subheadline)
                    .foregroundStyle(palette.green)
                    .lineLimit(2)

                Text("\(findingPlayer) → \(receivingPlayer)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !hint.entrance.isEmpty {
                    Text(hint.entrance)
                        .font(.caption2)
                        .foregroundStyle(palette.blue)
                }
            }
        }
        .opacity(isFound ? 0.72 : 1)
    }

    @ViewBuilder
    private var statusControl: some View {
        let status = isFound ? HintStatus.found : hint.status
        let color = status.uiColor(for: colorScheme)

        if isFound {
            statusBadge(status: status, color: color)
        } else if canEdit {
            Menu {
                ForEach(HintStatus.selectableCases, id: \.rawValue) { option in
                    Button {
                        onStatusChange(option)
                    } label: {
                        Label(option.menuTitle, systemImage: option.systemImage)
                    }
                }
            } label: {
                statusBadge(status: status, color: color)
            }
            .buttonStyle(.borderless)
        } else {
            statusBadge(status: status, color: color)
                .opacity(0.85)
        }
    }

    private func statusBadge(status: HintStatus, color: Color) -> some View {
        Image(systemName: status.systemImage)
            .font(.body.weight(.semibold))
            .foregroundStyle(color)
            .frame(width: 34, height: 34)
            .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityLabel("Hint status: \(status.menuTitle)")
    }
}

struct HintInputView: View {
    @ObservedObject var context: APContext
    @Binding var query: String

    private var suggestions: [String] {
        guard !context.activeGameName.isEmpty else { return [] }
        let names = context.nameLookup.itemNames(for: context.activeGameName)
        guard !query.isEmpty else { return [] }
        return names.filter { $0.localizedCaseInsensitiveContains(query) }.prefix(8).map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("New hint item name", text: $query)
                    .textFieldStyle(.roundedBorder)
                Button("!hint") {
                    guard !query.isEmpty else { return }
                    context.sendSay("!hint \(query)")
                    query = ""
                }
                .buttonStyle(.borderedProminent)
            }
            if !suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(suggestions, id: \.self) { suggestion in
                            Button(suggestion) {
                                query = suggestion
                            }
                            .buttonStyle(.bordered)
                            .font(.caption)
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}
