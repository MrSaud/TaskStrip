import SwiftUI

/// The step between "export" and a file on disk.
///
/// It exists for one reason: passwords. A backup without a passphrase carries none — that's
/// Android's rule and this keeps it — so the choice has to be put in front of the user rather
/// than made quietly either way.
struct ExportBackupSheet: View {
    let contents: BackupExport.Contents
    let onExport: (String) -> Void
    let onCancel: () -> Void

    @State private var includePasswords = false
    @State private var passphrase = ""
    @State private var confirmation = ""

    private var credentialsWithPasswords: Int {
        contents.credentials.filter { CredentialStore.shared.hasPassword(for: $0.id) }.count
    }

    private var passphraseMatches: Bool {
        !passphrase.isEmpty && passphrase == confirmation
    }

    private var canExport: Bool {
        !includePasswords || passphraseMatches
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Export backup")
                    .font(.title2.weight(.semibold))
                Text(summary)
                    .foregroundStyle(.secondary)
            }

            if credentialsWithPasswords > 0 {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: $includePasswords) {
                        Text("Include \(credentialsWithPasswords) saved password\(credentialsWithPasswords == 1 ? "" : "s")")
                    }
                    if includePasswords {
                        SecureField("Passphrase", text: $passphrase)
                        SecureField("Passphrase again", text: $confirmation)
                        if !passphrase.isEmpty && !passphraseMatches {
                            Text("The two don't match.")
                                .font(.caption)
                                .foregroundStyle(TaskStripTheme.urgent)
                        }
                        // There is nowhere to look it up: the passphrase isn't stored here or in
                        // the file, which is what makes the file safe to move around.
                        Text("Passwords are encrypted with this and nothing else. Lose it and "
                             + "they can't be recovered from the backup.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Without a passphrase the credentials still travel — usernames, URLs "
                             + "and notes — but their passwords stay on this Mac.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .textFieldStyle(.roundedBorder)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(TaskStripTheme.baySurface, in: RoundedRectangle(cornerRadius: 8))
            }

            Label(
                "Restoring this on the phone replaces everything there — it's a restore, not a merge.",
                systemImage: "exclamationmark.triangle"
            )
            .font(.callout)
            .foregroundStyle(TaskStripTheme.high)

            Spacer(minLength: 0)

            HStack {
                Button("Cancel", role: .cancel) { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Choose Location…") { onExport(includePasswords ? passphrase : "") }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canExport)
            }
        }
        .padding(20)
        .frame(width: 460, height: credentialsWithPasswords > 0 ? 430 : 260)
        .background(TaskStripTheme.bayBackground)
    }

    private var summary: String {
        var parts: [String] = []
        parts.append("\(contents.tasks.count) strip\(contents.tasks.count == 1 ? "" : "s")")
        if !contents.notes.isEmpty { parts.append("\(contents.notes.count) note\(contents.notes.count == 1 ? "" : "s")") }
        if !contents.reminders.isEmpty { parts.append("\(contents.reminders.count) reminder\(contents.reminders.count == 1 ? "" : "s")") }
        if !contents.storageItems.isEmpty { parts.append("\(contents.storageItems.count) file\(contents.storageItems.count == 1 ? "" : "s")") }
        if !contents.credentials.isEmpty { parts.append("\(contents.credentials.count) credential\(contents.credentials.count == 1 ? "" : "s")") }
        return parts.formatted(.list(type: .and))
    }
}
