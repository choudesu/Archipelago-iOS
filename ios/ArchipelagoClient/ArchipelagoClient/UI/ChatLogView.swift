import SwiftUI

struct ChatLogView: View {
    @ObservedObject var viewModel: AppViewModel

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
                        Text(renderedText(for: entry))
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(entry.isCommandEcho ? .orange : .primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(entry.id)
                    }
                }
                .padding()
            }
            .onChange(of: viewModel.context.chatLog.count) { _, _ in
                if let last = viewModel.context.chatLog.last {
                    withAnimation {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func renderedText(for entry: ChatLogEntry) -> String {
        if entry.attributedParts.isEmpty {
            return entry.text
        }
        let context = viewModel.context
        let renderer = JSONMessageRenderer(
            playerNames: context.playerNames,
            nameLookup: context.nameLookup,
            slot: context.slot,
            slotInfo: context.slotInfo
        )
        return renderer.render(entry.attributedParts)
    }
}
