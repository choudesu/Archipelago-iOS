import SwiftUI

struct ChatLogView: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    if viewModel.context.chatLog.isEmpty {
                        Text("Connection and chat messages appear here.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    ForEach(viewModel.context.chatLog) { entry in
                        messageView(for: entry)
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(entry.id)
                    }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: viewModel.context.chatLog.count) { _, _ in
                if let last = viewModel.context.chatLog.last {
                    withAnimation {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func messageView(for entry: ChatLogEntry) -> some View {
        if entry.attributedParts.isEmpty {
            Text(entry.text)
                .foregroundStyle(
                    entry.isCommandEcho
                        ? APArchipelagoColors.palette(for: colorScheme).orange
                        : Color.primary
                )
        } else {
            Text(renderedMessage(for: entry))
        }
    }

    private func renderedMessage(for entry: ChatLogEntry) -> AttributedString {
        let context = viewModel.context
        let renderer = JSONMessageRenderer(
            playerNames: context.playerNames,
            nameLookup: context.nameLookup,
            slot: context.slot,
            slotInfo: context.slotInfo,
            slotConcernsSelf: context.slotConcernsSelf,
            colorScheme: colorScheme
        )
        return renderer.renderAttributed(entry.attributedParts)
    }
}
