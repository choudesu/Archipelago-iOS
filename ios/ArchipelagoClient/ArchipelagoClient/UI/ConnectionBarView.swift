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
                    set: { viewModel.context.displayAddress = $0 }
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

            if let total = viewModel.context.totalLocations, total > 0 {
                ProgressView(value: viewModel.context.progressValue) {
                    Text("Checks: \(viewModel.context.checkedLocations.count)/\(total)")
                        .font(.caption)
                }
            }

            ConnectionInfoView(context: viewModel.context)
        }
        .padding(.horizontal)
    }
}

struct ConnectionInfoView: View {
    @ObservedObject var context: APContext

    var body: some View {
        if context.isConnected {
            VStack(alignment: .leading, spacing: 4) {
                if let slot = context.slot, let team = context.team {
                    Text("Slot \(slot) · Team \(team + 1) · \(context.game)")
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
        }
    }
}
