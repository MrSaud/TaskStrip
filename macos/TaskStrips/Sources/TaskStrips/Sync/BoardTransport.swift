import Foundation

/// Where the shared board lives, as the only thing a sync needs to know about it.
///
/// The same split SyncNoteTransport makes, and for the same reason: the merge doesn't care where
/// the bytes came from. The phone reaches Drive over its REST API because it has no other choice;
/// a Mac with Drive for desktop already has the folder mounted in Finder, where reading a file is
/// simpler and needs no sign-in. Both write the same names into the same folder, so a phone on the
/// API and a Mac on the mounted folder sync with each other perfectly well.
///
/// Files are addressed by hash — see SyncFileStore — which is what lets this protocol stay this
/// small. There is no "replace a file", because a changed file is a different name; no conflict to
/// report, because identical content is the same name; and nothing to version.
protocol BoardTransport {
    /// The document, or nil if the folder hasn't got one yet.
    ///
    /// Nil and "unreadable" mean the same thing to a merge — nothing to add — and neither may
    /// empty this device.
    func loadDocument() async throws -> Data?
    func saveDocument(_ data: Data) async throws

    /// Every file already in the shared folder, by hash. What the upload set is subtracted from.
    func remoteHashes() async throws -> Set<String>

    func download(hash: String) async throws -> Data
    func upload(hash: String, data: Data) async throws

    /// Only ever called for a hash no live record mentions — see SyncFileStore.orphans, which is
    /// computed against the merged document rather than one device's half.
    func deleteFile(hash: String) async throws
}
