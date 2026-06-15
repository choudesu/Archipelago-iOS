import SwiftUI
import UniformTypeIdentifiers

struct ConnectionBookmarkTransferHandlers: ViewModifier {
    @ObservedObject var viewModel: AppViewModel
    @Binding var exportRequest: Bool
    @Binding var importRequest: Bool

    @State private var showExporter = false
    @State private var exportDocument = ConnectionBookmarksDocument()
    @State private var showImporter = false
    @State private var pendingImportData: Data?
    @State private var pendingImportCount = 0
    @State private var showImportChoice = false

    func body(content: Content) -> some View {
        content
            .onChange(of: exportRequest) { _, requested in
                guard requested else { return }
                exportRequest = false
                beginExport()
            }
            .onChange(of: importRequest) { _, requested in
                guard requested else { return }
                importRequest = false
                showImporter = true
            }
            .fileExporter(
                isPresented: $showExporter,
                document: exportDocument,
                contentType: .json,
                defaultFilename: "archipelago-bookmarks"
            ) { result in
                if case .failure(let error) = result {
                    viewModel.presentError("Export Failed", error.localizedDescription)
                }
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                handleImportSelection(result)
            }
            .confirmationDialog(
                "Import Bookmarks",
                isPresented: $showImportChoice,
                titleVisibility: .visible
            ) {
                Button("Add to existing") {
                    performImport(replace: false)
                }
                Button("Replace all", role: .destructive) {
                    performImport(replace: true)
                }
                Button("Cancel", role: .cancel) {
                    pendingImportData = nil
                }
            } message: {
                Text("Import \(pendingImportCount) bookmark(s)? Exported files may include saved passwords.")
            }
    }

    private func beginExport() {
        do {
            exportDocument = try viewModel.makeExportDocument()
            showExporter = true
        } catch {
            viewModel.presentError("Export Failed", error.localizedDescription)
        }
    }

    private func handleImportSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            viewModel.presentError("Import Failed", error.localizedDescription)
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                let data = try viewModel.readBookmarkImportData(from: url)
                let count = try viewModel.countImportableBookmarks(in: data)
                guard count > 0 else {
                    throw ConnectionBookmarkTransferError.empty
                }
                pendingImportData = data
                pendingImportCount = count
                showImportChoice = true
            } catch {
                viewModel.presentError("Import Failed", error.localizedDescription)
            }
        }
    }

    private func performImport(replace: Bool) {
        guard let data = pendingImportData else { return }
        pendingImportData = nil
        do {
            let count = try viewModel.importBookmarks(data: data, replace: replace)
            viewModel.presentError("Import Complete", "Imported \(count) bookmark(s).")
        } catch {
            viewModel.presentError("Import Failed", error.localizedDescription)
        }
    }
}

extension View {
    func connectionBookmarkTransferHandlers(
        viewModel: AppViewModel,
        exportRequest: Binding<Bool>,
        importRequest: Binding<Bool>
    ) -> some View {
        modifier(ConnectionBookmarkTransferHandlers(
            viewModel: viewModel,
            exportRequest: exportRequest,
            importRequest: importRequest
        ))
    }
}
