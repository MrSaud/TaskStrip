import AppKit
import SwiftUI

/// Backups on Drive, mirroring the second half of BackupScreen.kt — back up now, and the list of
/// what's up there to restore from.
///
/// The phone puts its backups in a folder called TaskStripBackups; this reads and writes the same
/// one, so a backup made on either device shows up on the other.
struct DriveBackupsView: View {
    @ObservedObject private var session = DriveSession.shared
    @Environment(\.dismiss) private var dismiss

    /// What to upload when asked, and what to do with a downloaded archive.
    let contents: BackupExport.Contents
    let onRestore: (Data) -> Void

    @State private var backups: [DriveBackup] = []
    @State private var status: String?
    @State private var problem: String?
    @State private var isWorking = false
    @State private var hasLoaded = false
    @State private var passphrase = ""
    @State private var includePasswords = false

    private var credentialsWithPasswords: Int {
        contents.credentials.filter { CredentialStore.shared.hasPassword(for: $0.id) }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Google Drive")
                .font(.title2.weight(.semibold))

            if !session.isConfigured {
                notConfigured
            } else if !session.isSignedIn {
                signedOut
            } else {
                signedIn
            }

            Spacer(minLength: 0)

            HStack {
                if let status {
                    Text(status)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520, height: 460)
        .background(TaskStripTheme.bayBackground)
        .alert("Drive trouble", isPresented: Binding(
            get: { problem != nil },
            set: { if !$0 { problem = nil } }
        )) {
            Button("OK") { problem = nil }
        } message: {
            Text(problem ?? "")
        }
        .task {
            guard session.isSignedIn, !hasLoaded else { return }
            hasLoaded = true
            await refresh()
        }
    }

    private var notConfigured: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Not set up yet", systemImage: "exclamationmark.triangle")
                .foregroundStyle(TaskStripTheme.high)
            Text("Drive needs an OAuth client id from the same Google Cloud project as the phone "
                 + "app. Add it in Settings (⌘,) and come back.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var signedOut: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sign in to reach the backups this app keeps on your Drive.")
                .foregroundStyle(.secondary)
            Text("It asks for the drive.file scope only: files this app created, never anything "
                 + "else in your Drive.")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Button("Sign In with Google") {
                Task { await run { try await session.signIn(); await refresh() } }
            }
            .disabled(isWorking)
        }
    }

    private var signedIn: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button("Back Up Now") { Task { await backUp() } }
                    .disabled(isWorking)
                Button("Refresh") { Task { await refresh() } }
                    .disabled(isWorking)
                Spacer()
                Button("Sign Out") { session.signOut(); backups = [] }
                    .disabled(isWorking)
            }

            if credentialsWithPasswords > 0 {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Include \(credentialsWithPasswords) saved password\(credentialsWithPasswords == 1 ? "" : "s")", isOn: $includePasswords)
                    if includePasswords {
                        SecureField("Passphrase", text: $passphrase)
                            .textFieldStyle(.roundedBorder)
                        Text("Lose this and the passwords in the backup can't be recovered.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .background(TaskStripTheme.baySurface, in: RoundedRectangle(cornerRadius: 6))
            }

            Text("BACKUPS ON DRIVE")
                .font(.caption.weight(.semibold))
                .foregroundStyle(TaskStripTheme.amber)

            if backups.isEmpty {
                Text(isWorking ? "Looking…" : "Nothing up there yet.")
                    .foregroundStyle(.secondary)
            } else {
                List(backups) { backup in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(backup.name)
                            HStack(spacing: 8) {
                                if let createdAt = backup.createdAt {
                                    Text(createdAt.formatted(date: .abbreviated, time: .shortened))
                                }
                                if !backup.readableSize.isEmpty { Text(backup.readableSize) }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Restore…") { Task { await restore(backup) } }
                            .disabled(isWorking)
                    }
                    .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    // MARK: - Work

    private func run(_ work: @escaping () async throws -> Void) async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await work()
        } catch let error as DriveError {
            if error != .signInCancelled { problem = error.errorDescription }
        } catch {
            problem = error.localizedDescription
        }
    }

    private func refresh() async {
        await run {
            let client = try await session.client()
            let folder = try await client.ensureBackupFolder()
            backups = try await client.backups(inFolder: folder)
            status = backups.isEmpty ? nil : "\(backups.count) backup\(backups.count == 1 ? "" : "s") on Drive."
        }
    }

    private func backUp() async {
        await run {
            let result = try BackupExport.archive(
                contents,
                passphrase: includePasswords ? passphrase : "",
                store: .shared,
                credentialStore: .shared
            )
            let client = try await session.client()
            let folder = try await client.ensureBackupFolder()
            let name = BackupExport.suggestedFileName()
            try await client.upload(result.archive, named: name, toFolder: folder)
            status = "Uploaded \(name)."
            backups = try await client.backups(inFolder: folder)
        }
    }

    /// Hands the archive back to the board, which runs it through the same confirmation sheet a
    /// file picked off disk goes through — including the choice between adding and replacing.
    private func restore(_ backup: DriveBackup) async {
        await run {
            let client = try await session.client()
            let data = try await client.download(backup)
            status = "Read \(backup.name)."
            onRestore(data)
            dismiss()
        }
    }
}
