import SwiftUI

struct ConnectionSessionPickerView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(viewModel.sessionManager.sessions) { session in
                        sessionChip(session)
                    }
                    Button {
                        viewModel.addSession()
                    } label: {
                        Label("Add Slot", systemImage: "plus")
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                }
            }

            if viewModel.sessionManager.sessions.count > 1 {
                HStack {
                    Text("Background sync uses:")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Picker("Primary slot", selection: primaryBinding) {
                        ForEach(viewModel.sessionManager.sessions) { session in
                            Text(session.label).tag(session.id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
            }
        }
    }

    private var primaryBinding: Binding<UUID> {
        Binding(
            get: { viewModel.sessionManager.primarySessionID },
            set: { viewModel.setPrimarySession($0) }
        )
    }

    @ViewBuilder
    private func sessionChip(_ session: ConnectionSession) -> some View {
        let isActive = session.id == viewModel.activeSessionID
        let context = viewModel.sessionManager.context(for: session.id)
        let isConnected = context?.isConnected == true
        let isConnecting = context?.connectionState == .connecting

        Button {
            viewModel.selectSession(session.id)
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor(connected: isConnected, connecting: isConnecting))
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.label)
                        .font(.caption.weight(isActive ? .semibold : .medium))
                        .lineLimit(1)
                    Text(session.displaySubtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isActive ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: isActive ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            if viewModel.sessionManager.sessions.count > 1 {
                Button(role: .destructive) {
                    viewModel.removeSession(session.id)
                } label: {
                    Label("Remove Slot", systemImage: "trash")
                }
            }
            if isConnected {
                Button("Disconnect") {
                    viewModel.sessionManager.disconnect(sessionID: session.id)
                }
            } else if isActive {
                Button("Connect") {
                    viewModel.connect()
                }
            }
        }
    }

    private func statusColor(connected: Bool, connecting: Bool) -> Color {
        if connected { return .green }
        if connecting { return .orange }
        return .secondary.opacity(0.5)
    }
}
