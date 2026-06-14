import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ContentView: View {
    @StateObject private var viewModel = AppViewModel()
    @AppStorage(AppearanceMode.storageKey) private var appearanceModeRaw = AppearanceMode.defaultMode.rawValue
    @Environment(\.scenePhase) private var scenePhase

    private var appearanceMode: AppearanceMode {
        AppearanceMode(rawValue: appearanceModeRaw) ?? .defaultMode
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                ConnectionBarView(viewModel: viewModel)

                TabView(selection: $viewModel.selectedTab) {
                    ChatLogView(viewModel: viewModel)
                        .tabItem { Label("Log", systemImage: "text.bubble") }
                        .tag(0)

                    HintsView(context: viewModel.context)
                        .tabItem { Label("Hints", systemImage: "lightbulb") }
                        .tag(1)

                    ConnectionBookmarksView(viewModel: viewModel)
                        .tabItem { Label("Bookmarks", systemImage: "bookmark") }
                        .tag(2)

                    SettingsView(viewModel: viewModel)
                        .tabItem { Label("Settings", systemImage: "gearshape") }
                        .tag(3)
                }
                .onChange(of: viewModel.selectedTab) { _, _ in
                    dismissKeyboard()
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
        .preferredColorScheme(appearanceMode.colorScheme)
        .onChange(of: scenePhase) { _, phase in
            let context = viewModel.context
            let joined = context.slot != nil
            let connected = context.isConnected
            switch phase {
            case .background:
                APNotificationService.shared.handleEnterBackground(joined: joined, connected: connected)
            case .active:
                APNotificationService.shared.handleEnterForeground(stillConnected: connected)
            case .inactive:
                break
            @unknown default:
                break
            }
        }
    }
}

#if canImport(UIKit)
private func dismissKeyboard() {
    UIApplication.shared.sendAction(
        #selector(UIResponder.resignFirstResponder),
        to: nil,
        from: nil,
        for: nil
    )
}
#else
private func dismissKeyboard() {}
#endif

struct SettingsView: View {
    @ObservedObject var viewModel: AppViewModel
    @AppStorage(AppearanceMode.storageKey) private var appearanceModeRaw = AppearanceMode.defaultMode.rawValue
    @AppStorage(Persistence.notificationsEnabledKey) private var notificationsEnabled = false
    @AppStorage(Persistence.connectionBookmarkChipsEnabledKey) private var bookmarkChipsEnabled = true
    @State private var deathLinkEnabled = Persistence.deathLinkEnabled
    @State private var requestBookmarkExport = false
    @State private var requestBookmarkImport = false

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $appearanceModeRaw) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.label).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }
            Section("Notifications") {
                Toggle("Disconnect Alerts", isOn: $notificationsEnabled)
                    .onChange(of: notificationsEnabled) { _, enabled in
                        if enabled {
                            Task { _ = await APNotificationService.shared.requestPermissionIfNeeded() }
                        }
                    }
                Text("Notifies you when the app moves to the background while connected. Allow notifications when prompted.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Connection Bookmarks") {
                Toggle("Quick-access chips", isOn: $bookmarkChipsEnabled)
                Button("Export Bookmarks") {
                    requestBookmarkExport = true
                }
                .disabled(viewModel.bookmarkStore.bookmarks.isEmpty)
                Button("Import Bookmarks") {
                    requestBookmarkImport = true
                }
                Text("Export or import bookmark presets as JSON. Exported files may include saved passwords.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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
        .scrollDismissesKeyboard(.interactively)
        .connectionBookmarkTransferHandlers(
            viewModel: viewModel,
            exportRequest: $requestBookmarkExport,
            importRequest: $requestBookmarkImport
        )
    }
}

#Preview {
    ContentView()
}
