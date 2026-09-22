import SwiftUI

/// What the editor hands back — including the password, which the caller writes to the keychain.
/// Kept out of the model for the same reason it's kept out of the store.
struct CredentialDraft {
    var title: String = ""
    var username: String = ""
    var url: String = ""
    var notes: String = ""
    var password: String = ""
}

/// Creating and editing a saved login, mirroring CredentialEditScreen.kt.
struct CredentialEditView: View {
    let onSave: (CredentialDraft) -> Void
    let onCancel: () -> Void

    @State private var draft: CredentialDraft
    @State private var isPasswordVisible = false

    private let isEditing: Bool

    init(
        credential: Credential?,
        password: String,
        onSave: @escaping (CredentialDraft) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.onSave = onSave
        self.onCancel = onCancel
        isEditing = credential != nil

        var draft = CredentialDraft()
        if let credential {
            draft.title = credential.title
            draft.username = credential.username
            draft.url = credential.url
            draft.notes = credential.notes
            draft.password = password
        }
        _draft = State(initialValue: draft)
    }

    private var canSave: Bool {
        !draft.title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("CREDENTIAL") {
                    TextField("What is it for?", text: $draft.title)
                        // See the note in ReminderEditView: the placeholder is not what the
                        // accessibility tree calls this field.
                        .accessibilityIdentifier("credentialTitle")
                    TextField("Username", text: $draft.username)
                    TextField("URL", text: $draft.url)
                }

                Section("PASSWORD") {
                    HStack {
                        // A password field you can't read back is no use when the point of the
                        // screen is to put a password somewhere you can find it again.
                        if isPasswordVisible {
                            TextField("Password", text: $draft.password)
                        } else {
                            SecureField("Password", text: $draft.password)
                        }
                        Button {
                            isPasswordVisible.toggle()
                        } label: {
                            Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)
                        .help(isPasswordVisible ? "Hide" : "Show")
                    }
                    Text("Kept in your login keychain, not in the app's store or its backups — a "
                         + "backup only carries it when you set a passphrase to encrypt it with.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("NOTES") {
                    TextField("Anything else", text: $draft.notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("Cancel", role: .cancel) { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(isEditing ? "Save" : "Create") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
            .padding(12)
        }
        .frame(width: 480, height: 520)
        .background(TaskStripTheme.bayBackground)
    }

    private func save() {
        var result = draft
        result.title = draft.title.trimmingCharacters(in: .whitespaces)
        result.username = draft.username.trimmingCharacters(in: .whitespaces)
        result.url = draft.url.trimmingCharacters(in: .whitespaces)
        result.notes = draft.notes.trimmingCharacters(in: .whitespaces)
        onSave(result)
    }
}
