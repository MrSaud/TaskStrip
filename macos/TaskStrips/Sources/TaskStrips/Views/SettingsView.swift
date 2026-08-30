import SwiftUI

enum AppSettingsKey {
    static let defaultPriority = "defaultPriority"
    static let defaultNotesRtl = "defaultNotesRtl"
    static let confirmBeforeDelete = "confirmBeforeDelete"
    static let dailyDigest = "dailyDigest"
    static let weeklyReview = "weeklyReview"
    static let autoBackup = "autoBackup"
    static let showQuote = "showQuoteOfTheDay"
    /// When the last automatic backup went up, so the next one knows whether a day has passed.
    static let lastAutoBackup = "lastAutoBackupAt"
}

/// The cmd-, window. Deliberately small: only settings that change something the app already
/// does, rather than a page of switches invented to fill it.
struct SettingsView: View {
    @AppStorage(AppSettingsKey.defaultPriority) private var defaultPriority = Priority.normal
    @AppStorage(AppSettingsKey.defaultNotesRtl) private var defaultNotesRtl = false
    @AppStorage(AppSettingsKey.confirmBeforeDelete) private var confirmBeforeDelete = true
    @AppStorage(AppSettingsKey.dailyDigest) private var dailyDigest = false
    @AppStorage(AppSettingsKey.weeklyReview) private var weeklyReview = false
    @AppStorage(AppSettingsKey.autoBackup) private var autoBackup = false
    @AppStorage(AppSettingsKey.showQuote) private var showQuote = true
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

            Section {
                Toggle("Quote of the day on the board", isOn: $showQuote)
            } footer: {
                // Worth being able to switch off: it's the one thing the app fetches from a
                // service the user never set up.
                Text("Fetched once a day from zenquotes.io. Everything else the app talks to is "
                     + "your own Drive.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Morning digest at 8am", isOn: $dailyDigest)
                Toggle("Week in review, Fridays at 5pm", isOn: $weeklyReview)
            } header: {
                Text("Summaries")
            } footer: {
                // Both are off by default: an app that starts sending notifications before being
                // asked is an app whose notifications get turned off wholesale.
                Text("Each says nothing on a day with nothing to report. They're worked out while "
                     + "the app is open, so one that fires after days of the Mac being shut "
                     + "describes the board as it was last seen.")
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
                Toggle("Back up to Drive daily", isOn: $autoBackup)
                    .disabled(!drive.isSignedIn)
            } header: {
                Text("Google Drive")
            } footer: {
                Text("A daily backup runs when the app is open and a day has passed since the "
                     + "last one — nothing wakes a Mac app that isn't running. "
                     + "Create an OAuth client of type iOS in the same Google Cloud project as the "
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
