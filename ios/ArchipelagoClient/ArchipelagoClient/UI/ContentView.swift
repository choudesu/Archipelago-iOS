import SwiftUI

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
        .preferredColorScheme(appearanceMode.colorScheme)
        .onChange(of: scenePhase) { _, phase in
            APNotificationService.shared.setAppActive(phase == .active)
        }
        .onAppear {
            APNotificationService.shared.setAppActive(scenePhase == .active)
        }
    }
}

struct SettingsView: View {
    @ObservedObject var viewModel: AppViewModel
    @AppStorage(AppearanceMode.storageKey) private var appearanceModeRaw = AppearanceMode.defaultMode.rawValue
    @AppStorage(Persistence.notificationsEnabledKey) private var notificationsEnabled = false
    @AppStorage(Persistence.notificationChatEnabledKey) private var notificationChatEnabled = true
    @AppStorage(Persistence.notificationItemsEnabledKey) private var notificationItemsEnabled = true
    @AppStorage(Persistence.notificationForegroundEnabledKey) private var notificationForegroundEnabled = false
    @State private var deathLinkEnabled = Persistence.deathLinkEnabled

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
                Toggle("Enable Notifications", isOn: $notificationsEnabled)
                    .onChange(of: notificationsEnabled) { _, enabled in
                        if enabled {
                            Task { _ = await APNotificationService.shared.requestPermissionIfNeeded() }
                        }
                    }
                if notificationsEnabled {
                    Toggle("Chat Messages", isOn: $notificationChatEnabled)
                    Toggle("Items & Traps Received", isOn: $notificationItemsEnabled)
                    Toggle("Notify While App Is Open", isOn: $notificationForegroundEnabled)
                    Text("Notifications require an active connection. iOS may suspend the app in the background.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
    }
}

#Preview {
    ContentView()
}
