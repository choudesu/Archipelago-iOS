import SwiftUI

struct ChatLogView: View {
    @ObservedObject var context: APContext

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(context.chatLog) { entry in
                        Text(renderedText(for: entry))
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(entry.isCommandEcho ? .orange : .primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(entry.id)
                    }
                }
                .padding()
            }
            .onChange(of: context.chatLog.count) { _, _ in
                if let last = context.chatLog.last {
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
        let renderer = JSONMessageRenderer(
            playerNames: context.playerNames,
            nameLookup: context.nameLookup,
            slot: context.slot,
            slotInfo: context.slotInfo
        )
        return renderer.render(entry.attributedParts)
    }
}
