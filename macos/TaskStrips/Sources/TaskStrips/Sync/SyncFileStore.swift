import CryptoKit
import Foundation

/// The shared pile of files, addressed by what's inside them.
///
/// Mirrors SyncFileStore.kt. Every file the board carries — a strip's photos and voice notes, the
/// storage library, a sketch's pages — lives remotely under one flat prefix, named by the SHA-256
/// of its bytes. That one choice is what keeps binaries out of the merge entirely:
///
/// - the same photo added on both devices hashes the same, so it uploads once;
/// - a changed file is a different name, never a second version of the same one, so "which copy
///   wins" is a question that cannot arise;
/// - a file is immutable once written, so an upload can never race a download;
/// - and what to clean up is a fact about the document rather than a history to keep.
///
/// Nothing here transfers anything. Deciding what should move is the same on both platforms and is
/// worth testing on its own; moving it belongs to the transports, which differ.
enum SyncFileStore {

    /// A name prefix, not a folder.
    ///
    /// Both devices write into the same shared folder — the phone through Drive's API, the Mac
    /// through the same folder mounted in Finder — so the layout has to be one thing. A real
    /// subfolder would mean teaching both Drive clients to make and find one; a prefix on the name
    /// needs nothing either of them can't already do.
    static let prefix = "file-"

    /// Read in blocks rather than whole: a video attachment can be hundreds of megabytes, and
    /// reading one into memory to hash it is how a sync runs a machine out of it.
    static func hash(contentsOf url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var digest = SHA256()
        while let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
            digest.update(data: chunk)
        }
        return string(from: digest.finalize())
    }

    static func hash(_ data: Data) -> String {
        string(from: SHA256.hash(data: data))
    }

    /// Where a hash lives in the shared folder. Must match SyncFileStore.kt exactly — the two
    /// devices write into the same folder and have to agree on the names.
    static func remoteName(_ hash: String) -> String { prefix + hash }

    /// True for a name this store owns, so a sweep can tell its own files from the documents
    /// sitting beside them.
    static func isStoreName(_ name: String) -> Bool { name.hasPrefix(prefix) }

    static func hash(fromRemoteName name: String) -> String? {
        guard isStoreName(name) else { return nil }
        let hash = String(name.dropFirst(prefix.count))
        return hash.isEmpty ? nil : hash
    }

    /// What this device has that the shared folder doesn't.
    static func toUpload(
        referenced: Set<String>,
        remote: Set<String>,
        localHashes: Set<String>
    ) -> Set<String> {
        referenced.intersection(localHashes).subtracting(remote)
    }

    /// What the board points at that this device hasn't got. Deliberately not "everything remote":
    /// a device shouldn't pull down a file no live record mentions just because it is there.
    static func toDownload(referenced: Set<String>, localHashes: Set<String>) -> Set<String> {
        referenced.subtracting(localHashes)
    }

    /// Files nothing points at any more.
    ///
    /// Only ever computed against a merged document, never against one device's half — a file that
    /// looks unreferenced here may be the only copy of something the other device still has on a
    /// strip it hasn't sent yet, and deleting on that basis would destroy it.
    static func orphans(remote: Set<String>, referenced: Set<String>) -> Set<String> {
        remote.subtracting(referenced)
    }

    private static func string(from digest: SHA256Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}
