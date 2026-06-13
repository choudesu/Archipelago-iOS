import SwiftUI

struct HintsView: View {
    @ObservedObject var context: APContext
    @State private var hintQuery = ""

    var body: some View {
        VStack(spacing: 8) {
            HintInputView(context: context, query: $hintQuery)

            if context.hints.isEmpty {
                ContentUnavailableView("No Hints", systemImage: "lightbulb", description: Text("Hints appear here after connecting."))
            } else {
                List(context.hints) { hint in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(itemName(for: hint))
                            .font(.headline)
                        Text("Location: \(locationName(for: hint))")
                            .font(.subheadline)
                        Text("From \(playerName(hint.findingPlayer)) to \(playerName(hint.receivingPlayer))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if !hint.entrance.isEmpty {
                            Text("Entrance: \(hint.entrance)")
                                .font(.caption2)
                        }
                        Menu(hint.status.displayName) {
                            ForEach(HintStatus.allCases, id: \.rawValue) { status in
                                Button(status.displayName) {
                                    context.updateHint(
                                        location: hint.location,
                                        findingPlayer: hint.findingPlayer,
                                        status: status
                                    )
                                }
                            }
                        }
                        .font(.caption)
                    }
                    .padding(.vertical, 4)
                }
                .dismissKeyboardOnScroll()
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

struct HintInputView: View {
    @ObservedObject var context: APContext
    @Binding var query: String

    private var suggestions: [String] {
        guard !context.game.isEmpty else { return [] }
        let names = context.nameLookup.itemNames(for: context.game)
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
                .dismissKeyboardOnScroll()
            }
        }
        .padding(.horizontal)
    }
}
