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
///
/// It knows nothing about Drive. Whether the document arrives over the REST API or off a folder
/// Drive for desktop is already mirroring is the transport's business, which is what lets a Mac
/// sync without signing in while the phone, which has no such option, keeps using the API.
struct SyncNoteSync {
    var transport: SyncNoteTransport

    func run(local: [SyncNoteRecord]) async throws -> SyncNoteOutcome {
        let remote = try await transport.load()
        let merged = SyncNoteDocument.merge(local: local, remote: remote)

        // Compared against what each side actually held, so "already up to date" means it, and a
        // sync that changed nothing doesn't rewrite the document for the sake of it.
        let pushed = merged != SyncNoteDocument.sorted(remote)
        let pulled = merged != SyncNoteDocument.sorted(local)

        if pushed { try await transport.save(merged) }

        return SyncNoteOutcome(merged: merged, pushed: pushed, pulled: pulled)
    }
}
