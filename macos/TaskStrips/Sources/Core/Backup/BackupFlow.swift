import Foundation
import SwiftData

/// Alert payload — `.alert(item:)` needs something Identifiable, and a bare String isn't.
struct ImportMessage: Identifiable {
    let id = UUID()
    let title: String
    let body: String
}

/// Writing a backup and reading one back, for both boards. Only choosing where the file goes (or
/// comes from) differs between the Mac and the iPhone/iPad — an open or save panel there, the
/// Files picker here — so everything after that choice lives here, once.
///
/// The split between the main actor and a detached task is the same on both: SwiftData objects
/// belong to the thread that made them, so reading the board and writing to it happen on the
/// main actor, and packing or unpacking bytes happens somewhere else while the screen stays alive.
@MainActor
enum BackupFlow {
    /// The part of an export that has to read the board.
    struct PreparedExport {
        let manifest: Data
        let mediaPaths: Set<String>
        let strips: Int
        let passwordsIncluded: Int
    }

    static func prepareExport(_ contents: BackupExport.Contents, passphrase: String) throws -> PreparedExport {
        var passwordsIncluded = 0
        let manifest = try BackupExport.manifestData(
            contents,
            passphrase: passphrase,
            credentialStore: .shared,
            passwordsIncluded: &passwordsIncluded
        )
        return PreparedExport(
            manifest: manifest,
            mediaPaths: BackupExport.mediaPaths(contents, store: .shared),
            strips: contents.tasks.count,
            passwordsIncluded: passwordsIncluded
        )
    }

    /// The zip, packed off the main actor. `progress` is called on the main actor.
    static func pack(
        _ prepared: PreparedExport,
        progress: @escaping @MainActor (Int, Int) -> Void
    ) async -> BackupExport.Result {
        let manifest = prepared.manifest
        let paths = prepared.mediaPaths
        var result = await Task.detached {
            BackupExport.archive(
                manifest: manifest,
                mediaPaths: paths,
                store: .shared,
                progress: { done, total in
                    Task { @MainActor in progress(done, total) }
                }
            )
        }.value
        result.passwordsIncluded = prepared.passwordsIncluded
        return result
    }

    static func exportMessage(_ result: BackupExport.Result, fileName: String, strips: Int) -> ImportMessage {
        var body = "Wrote \(strips) strip"
            + "\(strips == 1 ? "" : "s") and \(result.fileCount) file"
            + "\(result.fileCount == 1 ? "" : "s") to \(fileName)."
        if result.passwordsIncluded > 0 {
            body += " \(result.passwordsIncluded) password"
                + "\(result.passwordsIncluded == 1 ? " is" : "s are") encrypted with your passphrase."
        }
        if result.filesMissing > 0 {
            body += " \(result.filesMissing) file\(result.filesMissing == 1 ? "" : "s") named by a strip "
                + "couldn't be read, so \(result.filesMissing == 1 ? "it isn't" : "they aren't") in the backup."
        }
        return ImportMessage(title: "Backup written", body: body)
    }

    /// Reads a backup's manifest for the summary sheet. Parsing writes nothing: the files are only
    /// fetched if the user commits.
    static func readSummary(at url: URL) throws -> BackupImportSummary {
        var summary = try BackupImport.parse(manifest: BackupArchive.manifestData(at: url))
        summary.sourceURL = url
        return summary
    }

    /// The backup's files, unpacked off the main actor. Returns the paths actually written, or the
    /// reason none could be.
    static func restoreMedia(
        for summary: BackupImportSummary,
        progress: @escaping @MainActor (Int, Int) -> Void
    ) async -> (restored: Set<String>, problem: String?) {
        let referenced = summary.referencedMediaPaths
        guard let source = summary.sourceURL, !referenced.isEmpty else { return ([], nil) }
        return await Task.detached { () -> (Set<String>, String?) in
            do {
                let restored = try BackupImport.restoreMedia(
                    fromArchiveAt: source,
                    paths: referenced,
                    into: .shared,
                    progress: { done, total in
                        Task { @MainActor in progress(done, total) }
                    }
                )
                return (restored, nil)
            } catch {
                return ([], error.localizedDescription)
            }
        }.value
    }

    /// Everything that touches the store, and the message that says what happened.
    static func apply(
        _ summary: BackupImportSummary,
        mode: ImportMode,
        passphrase: String,
        restored: Set<String>,
        mediaProblem: String?,
        existing: BackupExport.Contents,
        context: ModelContext
    ) -> ImportMessage {
        let replaced = mode == .replace ? existing.tasks.count : 0
        let referenced = summary.referencedMediaPaths

        let imported = BackupImport.apply(summary.tasks, mode: mode, existing: existing.tasks, context: context)
        let importedNotes = BackupImport.apply(notes: summary.notes, mode: mode, existing: existing.notes, context: context)
        let importedFiles = BackupImport.apply(
            storageItems: summary.storageItems, mode: mode, existing: existing.storageItems, context: context
        )
        let importedReminders = BackupImport.apply(
            reminders: summary.reminders, mode: mode, existing: existing.reminders, context: context
        )
        let importedCredentials = BackupImport.apply(
            credentials: summary.credentials,
            mode: mode,
            existing: existing.credentials,
            passphrase: passphrase,
            store: .shared,
            context: context
        )

        // SwiftData autosaves, but a failure here is exactly the silent-save class of bug that bit
        // Phase 1 — an import that quietly wrote nothing would look identical to an empty backup.
        do {
            try context.save()
        } catch {
            return ImportMessage(
                title: "Import failed",
                body: "The strips couldn't be saved: \(error.localizedDescription)"
            )
        }

        var body = mode == .replace
            ? "Replaced \(replaced) strip\(replaced == 1 ? "" : "s") with \(imported) from the backup."
            : "Added \(imported) strip\(imported == 1 ? "" : "s") to the board."
        if importedNotes > 0 {
            body += " \(importedNotes) quick note\(importedNotes == 1 ? "" : "s") came across too."
        }
        if importedFiles > 0 {
            body += " \(importedFiles) file\(importedFiles == 1 ? "" : "s") joined the storage library."
        }
        if importedReminders > 0 {
            body += " \(importedReminders) standalone reminder\(importedReminders == 1 ? "" : "s") came across."
        }
        if importedCredentials.imported > 0 {
            body += " \(importedCredentials.imported) credential\(importedCredentials.imported == 1 ? "" : "s") came across"
            let withPasswords = importedCredentials.passwordsRestored
            if withPasswords == 0 {
                body += summary.hasEncryptedPasswords
                    ? ", but none of their passwords could be unlocked — check the passphrase."
                    : ", without passwords: the backup was written without a passphrase, so it carries none."
            } else {
                body += ", \(withPasswords) with \(withPasswords == 1 ? "its password" : "their passwords")."
            }
        }
        if !referenced.isEmpty {
            body += " Restored \(restored.count) of \(referenced.count) file\(referenced.count == 1 ? "" : "s")."
        }
        let missing = referenced.count - restored.count
        if missing > 0 {
            body += " The \(missing) the archive didn't carry show as missing on their strips."
        }
        if let mediaProblem {
            body += " Files couldn't be read: \(mediaProblem)"
        }
        return ImportMessage(title: "Import complete", body: body)
    }
}
