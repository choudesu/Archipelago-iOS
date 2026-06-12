import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = AppViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                ConnectionBarView(viewModel: viewModel)

                TabView(selection: $viewModel.selectedTab) {
                    ChatLogView(context: viewModel.context)
                        .tabItem { Label("Log", systemImage: "text.bubble") }
                        .tag(0)

                    HintsView(context: viewModel.context)
                        .tabItem { Label("Hints", systemImage: "lightbulb") }
                        .tag(1)

                    SettingsView(viewModel: viewModel)
                        .tabItem { Label("Settings", systemImage: "gearshape") }
                        .tag(2)
                }

                CommandInputView(viewModel: viewModel)
            }
            .navigationTitle("Archipelago \(APVersion.clientVersion.simpleString)")
            .navigationBarTitleDisplayMode(.inline)
            .alert(viewModel.errorTitle ?? "Error", isPresented: $viewModel.showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }
}

struct SettingsView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var deathLinkEnabled = Persistence.deathLinkEnabled

    var body: some View {
        Form {
            Section("Connection") {
                Text("Client UUID: \(Persistence.clientUUID)")
                    .font(.caption)
                    .textSelection(.enabled)
            }
            Section("Features") {
                Toggle("Death Link", isOn: $deathLinkEnabled)
                    .onChange(of: deathLinkEnabled) { _, newValue in
                        viewModel.context.updateDeathLink(newValue)
                    }
            }
            Section("Help") {
                Text(viewModel.commands.helpText())
                    .font(.caption)
            }
        }
    }
}

#Preview {
    ContentView()
}
