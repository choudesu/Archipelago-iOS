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
            VStack(spacing: 0) {
                ConnectionBarView(viewModel: viewModel)
                    .padding(.bottom, 8)

                TabView(selection: $viewModel.selectedTab) {
                    VStack(spacing: 0) {
                        ChatLogView(viewModel: viewModel)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        CommandInputView(viewModel: viewModel)
                    }
                    .tabItem { Label("Log", systemImage: "text.bubble") }
                    .tag(0)

                    HintsView(viewModel: viewModel)
                        .tabItem { Label("Hints", systemImage: "lightbulb") }
                        .tag(1)

                    TrackerTabView(viewModel: viewModel)
                        .tabItem { Label("Tracker", systemImage: "map") }
                        .tag(2)

                    ConnectionBookmarksView(viewModel: viewModel)
                        .tabItem { Label("Bookmarks", systemImage: "bookmark") }
                        .tag(3)

                    SettingsView(viewModel: viewModel)
                        .tabItem { Label("Settings", systemImage: "gearshape") }
                        .tag(4)
                }
                .id(viewModel.activeSessionID)
                .onChange(of: viewModel.selectedTab) { _, _ in
                    dismissKeyboard()
                }
            }
            .navigationTitle("Applepelago \(APVersion.clientVersion.simpleString)")
            .navigationBarTitleDisplayMode(.inline)
            .alert(viewModel.errorTitle ?? "Error", isPresented: $viewModel.showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .overlay(alignment: .top) {
                InAppNotificationBanner(center: viewModel.inAppNotifications) { notification in
                    if notification.kind == .hint {
                        viewModel.selectedTab = 1
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
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
                BackgroundSessionManager.shared.beginBackgroundGracePeriod {
                    context.persistActivitySnapshot()
                }
                BackgroundRefreshTask.schedule()
            case .active:
                BackgroundSessionManager.shared.endBackgroundGracePeriod()
                APNotificationService.shared.handleEnterForeground()
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
    @AppStorage(Persistence.activityAlertsEnabledKey) private var activityAlertsEnabled = true
    @AppStorage(Persistence.backgroundSyncEnabledKey) private var backgroundSyncEnabled = true
    @AppStorage(Persistence.connectionBookmarkChipsEnabledKey) private var bookmarkChipsEnabled = true
    @AppStorage(Persistence.clientModeKey) private var clientModeRaw = ClientMode.text.rawValue
    @State private var requestBookmarkExport = false
    @State private var requestBookmarkImport = false
    @State private var requestPackImport = false

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

                Toggle("Item & Hint Alerts", isOn: $activityAlertsEnabled)
                    .onChange(of: activityAlertsEnabled) { _, enabled in
                        if enabled {
                            Task { _ = await APNotificationService.shared.requestPermissionIfNeeded() }
                        }
                    }
                Text("In-app banners while open, and iOS notifications when backgrounded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Background Sync", isOn: $backgroundSyncEnabled)
                    .onChange(of: backgroundSyncEnabled) { _, enabled in
                        if enabled, viewModel.context.isConnected {
                            BackgroundRefreshTask.schedule()
                        }
                    }
                Text("Periodically reconnects in the background to check for new items and hints. Apple controls how often this runs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Client Mode") {
                Picker("Connection type", selection: $clientModeRaw) {
                    ForEach(ClientMode.allCases) { mode in
                        Text(mode.label).tag(mode.rawValue)
                    }
                }
                .onChange(of: clientModeRaw) { _, raw in
                    let mode = ClientMode(rawValue: raw) ?? .text
                    viewModel.setClientMode(mode)
                }
                Text("PopTracker mode uses Tracker AP tags, receives slot data, and can send location checks when a pack is loaded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            TrackerPackPickerView(viewModel: viewModel, requestImport: $requestPackImport)
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
                Toggle("Death Link", isOn: .constant(false))
                    .disabled(true)
                Text("Secret future feature")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        .popTrackerPackTransferHandlers(viewModel: viewModel, importRequest: $requestPackImport)
    }
}

#Preview {
    ContentView()
}
