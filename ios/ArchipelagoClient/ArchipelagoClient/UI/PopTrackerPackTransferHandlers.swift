import SwiftUI
import UniformTypeIdentifiers

struct PopTrackerPackTransferHandlers: ViewModifier {
    @ObservedObject var viewModel: AppViewModel
    @Binding var importRequest: Bool

    @State private var showImporter = false

    func body(content: Content) -> some View {
        content
            .onChange(of: importRequest) { _, requested in
                guard requested else { return }
                importRequest = false
                showImporter = true
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.zip, .folder],
                allowsMultipleSelection: false
            ) { result in
                handleImportSelection(result)
            }
    }

    private func handleImportSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            viewModel.presentError("Import Failed", error.localizedDescription)
        case .success(let urls):
            guard let url = urls.first else { return }
            Task {
                await viewModel.importPopTrackerPack(from: url)
            }
        }
    }
}

extension View {
    func popTrackerPackTransferHandlers(viewModel: AppViewModel, importRequest: Binding<Bool>) -> some View {
        modifier(PopTrackerPackTransferHandlers(viewModel: viewModel, importRequest: importRequest))
    }
}
