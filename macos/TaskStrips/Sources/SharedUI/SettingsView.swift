import SwiftUI

enum AppSettingsKey {
    static let defaultPriority = "defaultPriority"
    static let defaultNotesRtl = "defaultNotesRtl"
    static let confirmBeforeDelete = "confirmBeforeDelete"
    static let dailyDigest = "dailyDigest"
    static let weeklyReview = "weeklyReview"
    static let autoBackup = "autoBackup"
    static let showQuote = "showQuoteOfTheDay"
    static let showMenuBar = "showMenuBarGlance"
    /// When the last automatic backup went up, so the next one knows whether a day has passed.
    static let lastAutoBackup = "lastAutoBackupAt"
}

/// The outcome of the last move of passwords into iCloud Keychain, for Settings to show. Counts
/// only, like the report it comes from.
enum PasswordMoveStatus {
    private static let key = "credentials.lastMoveReport"

    static func record(_ report: CredentialStore.MigrationReport) {
        UserDefaults.standard.set(
            ["moved": report.moved, "alreadyMoved": report.alreadyMoved,
             "noPassword": report.noPassword, "failed": report.failed],
            forKey: key
        )
    }

    static var summary: String {
        guard let saved = UserDefaults.standard.dictionary(forKey: key) as? [String: Int] else {
            return CredentialStore.shared.hasMigrated
                ? "Passwords are kept in iCloud Keychain."
                : "Passwords will move to iCloud Keychain the next time the app starts."
        }
        let moved = (saved["moved"] ?? 0) + (saved["alreadyMoved"] ?? 0)
        let failed = saved["failed"] ?? 0
        if failed > 0 {
            return "\(moved) password\(moved == 1 ? "" : "s") in iCloud Keychain; \(failed) couldn't be "
                + "moved yet and will be tried again when the app next starts. Nothing has been lost: "
                + "the old copies are still in this Mac's keychain."
        }
        return "Passwords are kept in iCloud Keychain — \(moved) moved from this Mac's keychain, "
            + "where the old copies stay as a backup."
    }
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
    @AppStorage(AppSettingsKey.showMenuBar) private var showMenuBar = true
    @ObservedObject private var drive = DriveSession.shared
    @State private var clientID = GoogleOAuth.clientID() ?? ""
    @State private var clientIDProblem: String?

    var body: some View {
        Form {
            if BoardSync.isAllowed {
                SyncSettingsSection()
            }
            Section("Passwords") {
                Text(PasswordMoveStatus.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
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

            #if os(macOS)
            Section {
                Toggle("Show in the menu bar", isOn: $showMenuBar)
            } footer: {
                Text("Five open strips and three reminders, without opening the board.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            #endif

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
                     + "the app is open, so one that fires after days of \(Platform.thisDevice) being shut "
                     + "describes the board as it was last seen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Drive backup is the Mac's: the iPhone and iPad back up through Files, and Drive is
            // retired with Android in Phase 7.
            #if os(macOS)
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
            #endif
        }
        .formStyle(.grouped)
        #if os(macOS)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        #endif
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
