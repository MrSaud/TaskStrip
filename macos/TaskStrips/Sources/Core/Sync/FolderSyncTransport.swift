import Foundation

/// The shared document as a file on disk — the Drive for desktop folder, or any folder at all.
///
/// No sign-in, no token, no network: Drive for desktop is already syncing that folder, so writing
/// the file is the whole job. What that costs, and what most of this file is about, is that the
/// daemon does not merge. When two machines write the same file it keeps both, leaving the second
/// one beside the first with a decorated name and saying nothing. A sync that only ever read
/// `sync_notes.json` would silently never see the other device's edits — so this reads the
/// conflict copies too, folds them into the merge, and clears them away once their contents are
/// safely in the real document.
struct FolderSyncTransport: SyncNoteTransport {
    let folder: URL

    var documentURL: URL {
        folder.appending(path: SyncNoteDocument.fileName)
    }

    func load() async throws -> [SyncNoteRecord] {
        var notes = read(documentURL)
        for copy in conflictCopies() {
            notes = SyncNoteDocument.merge(local: notes, remote: read(copy))
        }
        return notes
    }

    func save(_ notes: [SyncNoteRecord]) async throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let data = try SyncNoteDocument.data(for: notes)

        // Written aside and moved into place, so Drive for desktop never gets a half-written file
        // to upload. A replaceItemAt keeps this atomic on the same volume.
        let staging = folder.appending(path: ".\(SyncNoteDocument.fileName).writing")
        try data.write(to: staging)
        if FileManager.default.fileExists(atPath: documentURL.path) {
            _ = try FileManager.default.replaceItemAt(documentURL, withItemAt: staging)
        } else {
            try FileManager.default.moveItem(at: staging, to: documentURL)
        }

        // Only now, with everything they held written into the real document, are the conflict
        // copies safe to remove. The merge is a union, so nothing in them can have been dropped.
        for copy in conflictCopies() {
            try? FileManager.default.removeItem(at: copy)
        }
    }

    /// A missing file and an unreadable one are the same answer: nothing to merge. Drive for
    /// desktop can leave a file present but not yet downloaded, and that must not read as "the
    /// other device deleted everything".
    private func read(_ url: URL) -> [SyncNoteRecord] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return SyncNoteDocument.notes(from: data)
    }

    /// What the daemon leaves behind: the same name with something inserted before the extension —
    /// `sync_notes (1).json`, `sync_notes (conflicted copy 2026-08-30).json`. Matched by shape
    /// rather than by an exact pattern, because the decoration differs by client and by version
    /// and getting it wrong loses an edit.
    func conflictCopies() -> [URL] {
        let stem = (SyncNoteDocument.fileName as NSString).deletingPathExtension
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil
        )) ?? []

        return contents.filter { url in
            let name = url.lastPathComponent
            return url.pathExtension.lowercased() == "json"
                && name != SyncNoteDocument.fileName
                && name.hasPrefix(stem)
        }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
