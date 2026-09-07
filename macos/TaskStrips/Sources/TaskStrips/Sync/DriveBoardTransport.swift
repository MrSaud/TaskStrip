import Foundation

/// The shared board over Drive's API — what a Mac uses when Drive for desktop isn't installed, and
/// the only thing the phone can use at all.
///
/// A class, like DriveSyncTransport and for the same reason: the folder id and the ids of the files
/// found while listing are reused afterwards, and looking them up again would be more round trips
/// for answers that cannot have changed in between.
final class DriveBoardTransport: BoardTransport {
    private let client: DriveClient
    private var folderID: String?
    private var documentID: String?
    /// Hash to Drive's own id, filled in by `remoteHashes`. Drive addresses files by an opaque id
    /// rather than by name, so downloading or deleting one means having listed it first.
    private var fileIDs: [String: String] = [:]

    init(client: DriveClient) {
        self.client = client
    }

    private func folder() async throws -> String {
        if let folderID { return folderID }
        let id = try await client.ensureBackupFolder()
        folderID = id
        return id
    }

    func loadDocument() async throws -> Data? {
        let folder = try await folder()
        guard let existing = try await client.file(named: SyncBoardDocument.fileName, inFolder: folder) else {
            documentID = nil
            return nil
        }
        documentID = existing.id
        return try await client.download(fileID: existing.id)
    }

    /// Replaced in place when it is already there, so the document keeps one id across syncs.
    ///
    /// Delete-and-recreate would leave anything holding the old id — another device mid-sync, a
    /// share link — pointing at nothing.
    func saveDocument(_ data: Data) async throws {
        let folder = try await folder()
        if let documentID {
            try await client.replace(fileID: documentID, with: data, mimeType: SyncBoardDocument.mimeType)
        } else {
            documentID = try await client.upload(
                data,
                named: SyncBoardDocument.fileName,
                toFolder: folder,
                mimeType: SyncBoardDocument.mimeType
            )
        }
    }

    /// One listing of the whole folder, filtered by name.
    ///
    /// The backups and the documents live in the same folder, so anything not carrying the file
    /// prefix is somebody else's and is passed over — see SyncFileStore.isStoreName.
    func remoteHashes() async throws -> Set<String> {
        let folder = try await folder()
        let contents = try await client.backups(inFolder: folder)
        fileIDs = contents.reduce(into: [:]) { found, entry in
            if let hash = SyncFileStore.hash(fromRemoteName: entry.name) { found[hash] = entry.id }
        }
        return Set(fileIDs.keys)
    }

    func download(hash: String) async throws -> Data {
        guard let id = fileIDs[hash] else { throw DriveError.malformedResponse }
        return try await client.download(fileID: id)
    }

    /// Skipped when the folder already has it.
    ///
    /// Not an optimisation: the name is the hash of the contents, so a file already there holds
    /// exactly these bytes. Uploading again would spend the bandwidth to change nothing, and leave
    /// two Drive files with one name.
    func upload(hash: String, data: Data) async throws {
        let folder = try await folder()
        guard fileIDs[hash] == nil else { return }
        let id = try await client.upload(
            data,
            named: SyncFileStore.remoteName(hash),
            toFolder: folder,
            mimeType: "application/octet-stream"
        )
        fileIDs[hash] = id
    }

    /// Nothing to do when it is already gone — two devices can sweep the same orphan, and the
    /// second one arriving to find it missing is the system working, not failing.
    func deleteFile(hash: String) async throws {
        guard let id = fileIDs[hash] else { return }
        try await client.delete(fileID: id)
        fileIDs[hash] = nil
    }
}
