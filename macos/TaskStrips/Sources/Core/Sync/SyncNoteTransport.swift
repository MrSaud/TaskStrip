import Foundation

/// Where the shared document lives, as the only thing the sync needs to know about it.
///
/// Two implementations, and the reason the split is worth having: the merge doesn't care where the
/// bytes came from. The phone reaches Drive over its REST API because it has no other choice; a
/// Mac with Drive for desktop already has the same folder mounted in Finder, and reading a file is
/// simpler and needs no sign-in. Both write the same `sync_notes.json` to the same folder, so a
/// phone on the API and a Mac on the mounted folder sync with each other perfectly well.
protocol SyncNoteTransport {
    /// What the other device left, or nothing at all. "Nothing" covers a document that isn't
    /// there yet and one that can't be read — both mean the same to a merge, and neither may
    /// empty this machine.
    func load() async throws -> [SyncNoteRecord]
    func save(_ notes: [SyncNoteRecord]) async throws
}

/// Talks to Drive's API. What the phone always does, and what a Mac does when Drive for desktop
/// isn't installed.
///
/// A class because the folder and file ids found during `load` are reused by `save` — looking them
/// up twice would be two more round trips for an answer that cannot have changed in between.
final class DriveSyncTransport: SyncNoteTransport {
    private let client: DriveClient
    private var folderID: String?
    private var fileID: String?

    init(client: DriveClient) {
        self.client = client
    }

    func load() async throws -> [SyncNoteRecord] {
        let folder = try await client.ensureBackupFolder()
        folderID = folder

        guard let existing = try await client.file(named: SyncNoteDocument.fileName, inFolder: folder) else {
            fileID = nil
            return []
        }
        fileID = existing.id
        return SyncNoteDocument.notes(from: try await client.download(fileID: existing.id))
    }

    func save(_ notes: [SyncNoteRecord]) async throws {
        guard let folder = folderID else { throw DriveError.malformedResponse }
        let data = try SyncNoteDocument.data(for: notes)

        if let fileID {
            try await client.replace(fileID: fileID, with: data, mimeType: SyncNoteDocument.mimeType)
        } else {
            fileID = try await client.upload(
                data,
                named: SyncNoteDocument.fileName,
                toFolder: folder,
                mimeType: SyncNoteDocument.mimeType
            )
        }
    }
}
