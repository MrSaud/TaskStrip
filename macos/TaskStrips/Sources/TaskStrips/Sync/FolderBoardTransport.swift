import Foundation

/// The shared board in a folder on disk — Drive for desktop's mirror of the same folder the phone
/// reaches over the API, or any folder both machines can see.
///
/// Mirrors FolderSyncTransport, which does this for the synced notes.
struct FolderBoardTransport: BoardTransport {
    let folder: URL

    private var documentURL: URL { folder.appending(path: SyncBoardDocument.fileName) }

    private func url(for hash: String) -> URL {
        folder.appending(path: SyncFileStore.remoteName(hash))
    }

    func loadDocument() async throws -> Data? {
        try? Data(contentsOf: documentURL)
    }

    /// Written to a neighbour and moved into place.
    ///
    /// A sync on the other machine may read this file at any moment, and Drive for desktop may
    /// start uploading it the instant it changes. Half a document is worse than a stale one, and
    /// a replacing move is the only way to be sure neither ever sees one.
    func saveDocument(_ data: Data) async throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let staging = folder.appending(path: ".\(SyncBoardDocument.fileName).writing")
        try data.write(to: staging, options: .atomic)
        _ = try FileManager.default.replaceItemAt(documentURL, withItemAt: staging)
    }

    func remoteHashes() async throws -> Set<String> {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil, options: [.skipsSubdirectoryDescendants]
        )) ?? []
        return Set(contents.compactMap { SyncFileStore.hash(fromRemoteName: $0.lastPathComponent) })
    }

    func download(hash: String) async throws -> Data {
        try Data(contentsOf: url(for: hash))
    }

    /// Skipped when it is already there.
    ///
    /// Not an optimisation — a file's name is the hash of its contents, so a file that exists
    /// under this name already holds exactly these bytes. Rewriting it would be work for no change
    /// and, in a folder Drive is watching, another upload for no change.
    func upload(hash: String, data: Data) async throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = url(for: hash)
        guard !FileManager.default.fileExists(atPath: destination.path) else { return }
        let staging = folder.appending(path: ".\(SyncFileStore.remoteName(hash)).writing")
        try data.write(to: staging, options: .atomic)
        _ = try? FileManager.default.replaceItemAt(destination, withItemAt: staging)
        // replaceItemAt leaves the staging file behind if the destination appeared in between,
        // which is exactly what a second device uploading the same photo looks like.
        try? FileManager.default.removeItem(at: staging)
    }

    func deleteFile(hash: String) async throws {
        try? FileManager.default.removeItem(at: url(for: hash))
    }
}
