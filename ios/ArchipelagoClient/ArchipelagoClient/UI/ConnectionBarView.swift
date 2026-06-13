import SwiftUI

struct ConnectionBarView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("host:38281", text: Binding(
                    get: {
                        viewModel.context.displayAddress.isEmpty
                            ? viewModel.context.suggestedAddress
                            : viewModel.context.displayAddress
                    },
                    set: {
                        viewModel.clearLoadedBookmarkPreview()
                        viewModel.context.displayAddress = $0
                    }
                ))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .textFieldStyle(.roundedBorder)
                .disabled(viewModel.context.isConnected)

                Button(viewModel.context.isConnected ? "Disconnect" : "Connect") {
                    if viewModel.context.isConnected {
                        viewModel.disconnect()
                    } else {
                        viewModel.connect()
                    }
                }
                .buttonStyle(.borderedProminent)
            }

            if !viewModel.context.isConnected {
                TextField("Slot name", text: Binding(
                    get: { viewModel.context.slotName },
                    set: { viewModel.context.setSlotName($0) }
                ))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
            }

            if !viewModel.context.isConnected {
                ConnectionBookmarkChipsView(viewModel: viewModel)
            }

            if let total = viewModel.context.totalLocations, total > 0 {
                ProgressView(value: viewModel.context.progressValue) {
                    Text("Checks: \(viewModel.context.checkedLocations.count)/\(total)")
                        .font(.caption)
                }
            }

            ConnectionInfoView(
                context: viewModel.context,
                loadedBookmarkName: viewModel.loadedBookmarkName
            )

            DataPackageStatusHost(context: viewModel.context)
        }
        .padding(.horizontal)
    }
}

struct ConnectionBookmarkChipsView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject private var bookmarkStore: ConnectionBookmarkStore

    init(viewModel: AppViewModel) {
        self.viewModel = viewModel
        self._bookmarkStore = ObservedObject(wrappedValue: viewModel.bookmarkStore)
    }

    var body: some View {
        if !bookmarkStore.bookmarks.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(bookmarkStore.bookmarks) { bookmark in
                        Button {
                            viewModel.loadBookmark(bookmark)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(bookmark.name)
                                    .font(.caption.weight(.medium))
                                    .lineLimit(1)
                                Text(bookmark.subtitle)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }
}

struct ConnectionInfoView: View {
    @ObservedObject var context: APContext
    var loadedBookmarkName: String?

    private var previewServer: String {
        let address = context.displayAddress.isEmpty ? context.serverAddress : context.displayAddress
        return address.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        if context.isConnected {
            VStack(alignment: .leading, spacing: 4) {
                if let slot = context.slot, let team = context.team {
                    let slotLabel = context.slotName.isEmpty
                        ? "Slot \(slot)"
                        : "\(context.slotName) · Slot \(slot)"
                    Text("\(slotLabel) · Team \(team + 1) · \(context.activeGameName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let hintCost = context.hintCost, let hintPoints = context.hintPoints {
                    Text("Hint cost: \(hintCost)% · Hint points: \(hintPoints)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        } else if context.connectionState == .connecting {
            Text("Connecting…")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if !previewServer.isEmpty || !context.slotName.isEmpty || loadedBookmarkName != nil {
            VStack(alignment: .leading, spacing: 4) {
                if let loadedBookmarkName {
                    Text("Bookmark: \(loadedBookmarkName)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                if !context.slotName.isEmpty, !previewServer.isEmpty {
                    Text("\(context.slotName) @ \(previewServer)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if !previewServer.isEmpty {
                    Text(previewServer)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if !context.slotName.isEmpty {
                    Text("Slot: \(context.slotName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("Tap Connect when ready.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

struct DataPackageStatusHost: View {
    @ObservedObject var context: APContext
    @State private var displayed: DataPackageStatusInfo?
    @State private var isVisible = false

    var body: some View {
        Group {
            if let displayed {
                DataPackageStatusBanner(info: displayed, isVisible: isVisible)
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.84), value: isVisible)
        .animation(.spring(response: 0.45, dampingFraction: 0.84), value: displayed?.id)
        .onChange(of: context.dataPackageStatus) { _, newStatus in
            handleStatusChange(newStatus)
        }
        .onAppear {
            if let status = context.dataPackageStatus {
                displayed = status
                isVisible = true
            }
        }
    }

    private func handleStatusChange(_ newStatus: DataPackageStatusInfo?) {
        if let newStatus {
            displayed = newStatus
            if !isVisible {
                isVisible = true
            }
            return
        }

        guard displayed != nil else { return }
        isVisible = false
        Task {
            try? await Task.sleep(nanoseconds: 450_000_000)
            if context.dataPackageStatus == nil {
                displayed = nil
            }
        }
    }
}

struct DataPackageStatusBanner: View {
    let info: DataPackageStatusInfo
    let isVisible: Bool

    @State private var gameIndex = 0
    @State private var scrollTask: Task<Void, Never>?

    private let rowHeight: CGFloat = 16
    private let gameScrollInterval: UInt64 = 1_200_000_000
    private let gameScrollAnimation: Double = 0.4

    var body: some View {
        HStack(spacing: 6) {
            Text(info.prefix)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            gameTicker
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .offset(y: isVisible ? 0 : -rowHeight - 8)
        .opacity(isVisible ? 1 : 0)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .onAppear {
            gameIndex = 0
            startScrollingIfNeeded()
        }
        .onDisappear {
            scrollTask?.cancel()
            scrollTask = nil
        }
        .onChange(of: info.id) { _, _ in
            gameIndex = 0
            restartScrolling()
        }
        .onChange(of: info.games) { _, _ in
            gameIndex = min(gameIndex, max(info.games.count - 1, 0))
            restartScrolling()
        }
    }

    @ViewBuilder
    private var gameTicker: some View {
        if info.games.isEmpty {
            Text("…")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if info.games.count == 1, let game = info.games.first {
            Text(game)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        } else {
            ZStack(alignment: .leading) {
                Text(info.games[gameIndex])
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(height: rowHeight, alignment: .leading)
                    .id("\(info.id)-\(gameIndex)")
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .move(edge: .top).combined(with: .opacity)
                        )
                    )
            }
            .frame(height: rowHeight, alignment: .leading)
            .clipped()
        }
    }

    private var accessibilityText: String {
        let games = info.games.joined(separator: ", ")
        return "\(info.prefix): \(games)"
    }

    private func restartScrolling() {
        scrollTask?.cancel()
        scrollTask = nil
        startScrollingIfNeeded()
    }

    private func startScrollingIfNeeded() {
        guard info.games.count > 1 else { return }
        scrollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: gameScrollInterval)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    withAnimation(.easeInOut(duration: gameScrollAnimation)) {
                        gameIndex = (gameIndex + 1) % info.games.count
                    }
                }
            }
        }
    }
}
