import SwiftUI

struct DebugToolsView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var syncRunning = false
    @State private var lastAction = ""

    private var status: ActivityDebugService.Status {
        ActivityDebugService.status(for: viewModel.context)
    }

    var body: some View {
        Section("Debug Mode") {
            Toggle("Enable Debug Tools", isOn: Binding(
                get: { Persistence.debugModeEnabled },
                set: { Persistence.debugModeEnabled = $0 }
            ))
            Text("Shows test controls for activity alerts, iOS notifications, and background sync.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        if Persistence.debugModeEnabled {
            Section("Activity Status") {
                statusRow("App active", status.isAppActive ? "yes" : "no")
                statusRow("Connected", status.isConnected ? "yes" : "no")
                statusRow("Slot", status.slot.map(String.init) ?? "none")
                statusRow("Live items", "\(status.liveItemCount)")
                statusRow("Live hints", "\(status.liveHintCount)")
                statusRow("Snapshot items", "\(status.snapshotItemCount)")
                statusRow("Snapshot hint keys", "\(status.snapshotHintKeyCount)")
                statusRow("Session saved", status.hasSessionCredentials ? "yes" : "no")
            }

            Section("In-App Banners") {
                debugButton("Simulate Item Banner") {
                    viewModel.debugSimulateItemBanner()
                }
                debugButton("Simulate Hint Banner") {
                    viewModel.debugSimulateHintBanner()
                }
                debugButton("Clear Router Dedup Cache") {
                    viewModel.debugClearRouterDedup()
                }
            }

            Section("iOS Notifications") {
                debugButton("Simulate Background Item Notification") {
                    viewModel.debugSimulateBackgroundItemNotification()
                }
                debugButton("Simulate Background Hint Notification") {
                    viewModel.debugSimulateBackgroundHintNotification()
                }
                debugButton("Simulate Disconnect Notification") {
                    viewModel.debugSimulateDisconnectNotification()
                }
                Text("Uses local notifications. Grant permission when prompted.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Real Code Paths") {
                debugButton("Trigger ReceivedItems Path") {
                    viewModel.debugTriggerReceivedItemsPath()
                }
                debugButton("Trigger PrintJSON Hint Path") {
                    viewModel.debugTriggerPrintJSONHintPath()
                }
                debugButton("Trigger refreshHints Path") {
                    viewModel.debugTriggerRefreshHintsPath()
                }
                Text("Exercises the same handlers used during a live connection.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Background Sync") {
                debugButton("Reset Activity Snapshot") {
                    viewModel.debugResetActivitySnapshot()
                }
                debugButton("Rewind Snapshot (force next diff)") {
                    viewModel.debugRewindSnapshot()
                }
                debugButton("Schedule BG Refresh (~5s)") {
                    viewModel.debugScheduleNearTermRefresh()
                }
                Button {
                    Task {
                        syncRunning = true
                        await viewModel.debugRunBackgroundSyncNow()
                        syncRunning = false
                    }
                } label: {
                    HStack {
                        Text("Run Background Sync Now")
                        Spacer()
                        if syncRunning {
                            ProgressView()
                        }
                    }
                }
                .disabled(syncRunning || !status.hasSessionCredentials)
                Text("Run Sync Now reconnects using saved server/slot credentials. Rewind Snapshot makes the next sync treat current items/hints as new.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Simulator BG task: e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@\"\(BackgroundRefreshTask.identifier)\"]")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            if !lastAction.isEmpty {
                Section("Last Action") {
                    Text(lastAction)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !viewModel.debugLog.isEmpty {
                Section("Debug Log") {
                    ForEach(Array(viewModel.debugLog.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Button("Clear Log", role: .destructive) {
                        viewModel.debugClearLog()
                    }
                }
            }
        }
    }

    private func statusRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
        .font(.caption)
    }

    private func debugButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title) {
            action()
            lastAction = title
        }
    }
}
