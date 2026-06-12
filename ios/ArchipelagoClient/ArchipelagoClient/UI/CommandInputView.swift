import SwiftUI

struct CommandInputView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let prompt = viewModel.context.awaitingInputPrompt {
                Text(prompt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Button("?") {
                    viewModel.context.appendLog(viewModel.commands.helpText())
                }
                .buttonStyle(.bordered)

                TextField(
                    viewModel.context.awaitingInputPrompt == nil
                        ? "Chat, /command, or !command"
                        : "Response required",
                    text: $viewModel.commandText
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    if viewModel.context.awaitingInputPrompt != nil {
                        viewModel.submitPromptInput()
                    } else {
                        viewModel.submitInput()
                    }
                }

                Button("Send") {
                    if viewModel.context.awaitingInputPrompt != nil {
                        viewModel.submitPromptInput()
                    } else {
                        viewModel.submitInput()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
}
