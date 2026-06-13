import SwiftUI

struct ConnectionBookmarksView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject private var bookmarkStore: ConnectionBookmarkStore

    @State private var showCreateSheet = false
    @State private var editingBookmark: ConnectionBookmark?
    @State private var editMode: EditMode = .inactive

    init(viewModel: AppViewModel) {
        self.viewModel = viewModel
        self._bookmarkStore = ObservedObject(wrappedValue: viewModel.bookmarkStore)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Bookmarks")
                    .font(.headline)
                Spacer()
                if !bookmarkStore.bookmarks.isEmpty {
                    Button(editMode.isEditing ? "Done" : "Edit") {
                        editMode = editMode.isEditing ? .inactive : .active
                    }
                }
                Button {
                    showCreateSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Save bookmark")
            }
            .padding(.horizontal)
            .padding(.bottom, 8)

            if bookmarkStore.bookmarks.isEmpty {
                ContentUnavailableView {
                    Label("No Bookmarks", systemImage: "bookmark")
                } description: {
                    Text("Save connection presets with + above.")
                } actions: {
                    Button("Save Bookmark") {
                        showCreateSheet = true
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(bookmarkStore.bookmarks) { bookmark in
                        BookmarkRow(
                            bookmark: bookmark,
                            onLoad: { viewModel.loadBookmark(bookmark) },
                            onEdit: { editingBookmark = bookmark }
                        )
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                viewModel.deleteBookmark(bookmark)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            viewModel.deleteBookmark(bookmarkStore.bookmarks[index])
                        }
                    }
                    .onMove { offsets, destination in
                        bookmarkStore.move(fromOffsets: offsets, toOffset: destination)
                    }
                }
                .listStyle(.insetGrouped)
                .environment(\.editMode, $editMode)
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            ConnectionBookmarkEditorView(
                mode: .create,
                initialName: viewModel.suggestedBookmarkName(),
                initialServerAddress: viewModel.currentServerAddress(),
                initialSlotName: viewModel.currentSlotName(),
                initialPassword: viewModel.currentPassword() ?? ""
            ) { name, serverAddress, slotName, password in
                viewModel.saveBookmark(
                    name: name,
                    serverAddress: serverAddress,
                    slotName: slotName,
                    password: password
                )
            }
        }
        .sheet(item: $editingBookmark) { bookmark in
            ConnectionBookmarkEditorView(mode: .edit(bookmark)) { name, serverAddress, slotName, password in
                viewModel.updateBookmark(
                    bookmark,
                    name: name,
                    serverAddress: serverAddress,
                    slotName: slotName,
                    password: password
                )
            }
        }
    }
}

private struct BookmarkRow: View {
    let bookmark: ConnectionBookmark
    let onLoad: () -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(bookmark.name)
                    .font(.body.weight(.medium))
                Text(bookmark.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Edit", action: onEdit)
                .buttonStyle(.bordered)
                .font(.caption)
            Button("Load", action: onLoad)
                .buttonStyle(.borderedProminent)
                .font(.caption)
        }
        .padding(.vertical, 2)
    }
}
