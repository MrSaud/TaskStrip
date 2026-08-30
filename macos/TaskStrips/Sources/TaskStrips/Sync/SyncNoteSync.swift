import Foundation

/// What one sync did, so the page can say something truthful rather than just "done".
struct SyncNoteOutcome: Equatable {
    var merged: [SyncNoteRecord]
    var pushed: Bool
    var pulled: Bool

    var summary: String {
        switch (pulled, pushed) {
        case (true, true): return "Sent your changes and took theirs."
        case (true, false): return "Took changes from the other device."
        case (false, true): return "Sent your changes."
        case (false, false): return "Already up to date."
        }
    }
}

/// One round trip: read the shared document, merge it with what's here, write it back if that
/// changed anything.
///
/// Read-merge-write rather than anything cleverer, because the merge is order-independent and
/// idempotent — running this twice in a row changes nothing the second time, and two devices
/// running it in either order end up holding the same notes.
struct SyncNoteSync {
    var client: DriveClient

    func run(local: [SyncNoteRecord]) async throws -> SyncNoteOutcome {
        let folderID = try await client.ensureBackupFolder()
        let existing = try await client.file(named: SyncNoteDocument.fileName, inFolder: folderID)

        let remote: [SyncNoteRecord]
        if let existing {
            remote = SyncNoteDocument.notes(from: try await client.download(fileID: existing.id))
        } else {
            remote = []
        }

        let merged = SyncNoteDocument.merge(local: local, remote: remote)
        // Compared against what each side actually held, so "already up to date" means it, and a
        // sync that changed nothing doesn't rewrite the document for the sake of it.
        let pushed = merged != SyncNoteDocument.sorted(remote)
        let pulled = merged != SyncNoteDocument.sorted(local)

        if pushed {
            let data = try SyncNoteDocument.data(for: merged)
            if let existing {
                try await client.replace(
                    fileID: existing.id, with: data, mimeType: SyncNoteDocument.mimeType
                )
            } else {
                try await client.upload(
                    data,
                    named: SyncNoteDocument.fileName,
                    toFolder: folderID,
                    mimeType: SyncNoteDocument.mimeType
                )
            }
        }

        return SyncNoteOutcome(merged: merged, pushed: pushed, pulled: pulled)
    }
}
