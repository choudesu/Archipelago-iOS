import SwiftUI

struct ConnectionBookmarkEditorView: View {
    enum Mode {
        case create
        case edit(ConnectionBookmark)
    }

    let mode: Mode
    let onSave: (String, String, String, String?) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var serverAddress: String
    @State private var slotName: String
    @State private var password: String
    @State private var clearPassword = false

    init(
        mode: Mode,
        initialName: String = "",
        initialServerAddress: String = "",
        initialSlotName: String = "",
        initialPassword: String = "",
        onSave: @escaping (String, String, String, String?) -> Void
    ) {
        self.mode = mode
        self.onSave = onSave
        switch mode {
        case .create:
            _name = State(initialValue: initialName)
            _serverAddress = State(initialValue: initialServerAddress)
            _slotName = State(initialValue: initialSlotName)
            _password = State(initialValue: initialPassword)
        case .edit(let bookmark):
            _name = State(initialValue: bookmark.name)
            _serverAddress = State(initialValue: bookmark.serverAddress)
            _slotName = State(initialValue: bookmark.slotName)
            _password = State(initialValue: "")
        }
    }

    private var navigationTitle: String {
        switch mode {
        case .create: "Save Bookmark"
        case .edit: "Edit Bookmark"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Bookmark") {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section("Connection") {
                    TextField("Server address", text: $serverAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    TextField("Slot name", text: $slotName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField(
                        passwordFieldPlaceholder,
                        text: $password
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    if case .edit = mode {
                        Toggle("Remove saved password", isOn: $clearPassword)
                    }
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }

    private var passwordFieldPlaceholder: String {
        switch mode {
        case .create:
            return "Password (optional)"
        case .edit:
            return "New password (optional)"
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !serverAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        let passwordToSave: String?
        if clearPassword {
            passwordToSave = ""
        } else if trimmedPassword.isEmpty {
            passwordToSave = nil
        } else {
            passwordToSave = trimmedPassword
        }
        onSave(
            name.trimmingCharacters(in: .whitespacesAndNewlines),
            serverAddress.trimmingCharacters(in: .whitespacesAndNewlines),
            slotName.trimmingCharacters(in: .whitespacesAndNewlines),
            passwordToSave
        )
        dismiss()
    }
}
