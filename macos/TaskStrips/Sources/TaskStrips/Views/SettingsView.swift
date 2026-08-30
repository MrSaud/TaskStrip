import SwiftUI

enum AppSettingsKey {
    static let defaultPriority = "defaultPriority"
    static let defaultNotesRtl = "defaultNotesRtl"
    static let confirmBeforeDelete = "confirmBeforeDelete"
}

/// The cmd-, window. Deliberately small: only settings that change something the app already
/// does, rather than a page of switches invented to fill it.
struct SettingsView: View {
    @AppStorage(AppSettingsKey.defaultPriority) private var defaultPriority = Priority.normal
    @AppStorage(AppSettingsKey.defaultNotesRtl) private var defaultNotesRtl = false
    @AppStorage(AppSettingsKey.confirmBeforeDelete) private var confirmBeforeDelete = true
    @ObservedObject private var drive = DriveSession.shared
    @State private var clientID = GoogleOAuth.clientID() ?? ""
    @State private var clientIDProblem: String?

    var body: some View {
        Form {
            Section("New strips") {
                Picker("Priority", selection: $defaultPriority) {
                    ForEach(Priority.allCases) { priority in
                        Text(priority.label).tag(priority)
                    }
                }
                Picker("Notes are written", selection: $defaultNotesRtl) {
                    Text("Left to right").tag(false)
                    Text("Right to left").tag(true)
                }
            }
            Section {
                Toggle("Ask before deleting a strip", isOn: $confirmBeforeDelete)
            } footer: {
                Text("Deleting a strip is permanent — archiving keeps it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Written with an explicit header rather than Section("Google Drive") { } footer: { }:
            // SwiftUI has a titled section and a section with a footer, but no initialiser that
            // takes both.
            Section {
                // Kept in the keychain rather than the repository: it identifies a Cloud project,
                // and it differs per install anyway.
                TextField("OAuth client id", text: $clientID)
                    .onSubmit(saveClientID)
                HStack {
                    Button("Save", action: saveClientID)
                    Spacer()
                    Text(drive.isSignedIn ? "Signed in" : (drive.isConfigured ? "Not signed in" : "Not set up"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let clientIDProblem {
                    Text(clientIDProblem)
                        .font(.caption)
                        .foregroundStyle(TaskStripTheme.urgent)
                }
            } header: {
                Text("Google Drive")
            } footer: {
                Text("Create an OAuth client of type iOS in the same Google Cloud project as the "
                     + "phone app, with bundle id com.saud.taskstrip.mac. Only the drive.file "
                     + "scope is used — files this app created, nothing else in your Drive. "
                     + "Sign in from File → Google Drive… (⇧⌘D).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func saveClientID() {
        do {
            try drive.setClientID(clientID)
            clientIDProblem = nil
        } catch {
            clientIDProblem = error.localizedDescription
        }
    }
}
