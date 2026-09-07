import Foundation

/// Everything one device holds, in the form that travels.
struct BoardSnapshot: Equatable {
    var tasks: [SyncTaskRecord] = []
    var reminders: [SyncReminderRecord] = []
    var storage: [SyncStorageRecord] = []
    var credentials: [SyncCredentialRecord] = []
    var sketches: [SyncSketchRecord] = []

    var isEmpty: Bool {
        tasks.isEmpty && reminders.isEmpty && storage.isEmpty && credentials.isEmpty && sketches.isEmpty
    }

    /// Every file this board still points at.
    var referencedHashes: Set<String> {
        SyncBoardDocument.referencedHashes(tasks, storage: storage, sketches: sketches)
    }

    /// Sorted the way the document sorts, so two snapshots holding the same rows compare equal
    /// whatever order they were assembled in.
    var normalised: BoardSnapshot {
        BoardSnapshot(
            tasks: SyncBoardDocument.sorted(tasks),
            reminders: SyncBoardDocument.sorted(reminders),
            storage: SyncBoardDocument.sorted(storage),
            credentials: SyncBoardDocument.sorted(credentials),
            sketches: SyncBoardDocument.sorted(sketches)
        )
    }
}

/// What one sync did, so a screen can say something truthful rather than just "done".
struct BoardSyncOutcome: Equatable {
    var merged = BoardSnapshot()
    var stance: SyncStance = .merge
    var pushed = false
    var pulled = false
    var uploaded: [String] = []
    var downloaded: [String] = []
    var sweptAway: [String] = []
    /// Set when the sync couldn't run at all — no folder chosen, not signed in — as opposed to
    /// running and finding nothing to do. Those are different things to tell somebody.
    var failureReason: String?

    var summary: String {
        if let failureReason { return failureReason }
        if stance == .adopt { return "Took the other device's board." }
        switch (pulled, pushed) {
        case (true, true): return "Sent your changes and took theirs."
        case (true, false): return "Took changes from the other device."
        case (false, true): return "Sent your changes."
        case (false, false): return "Already up to date."
        }
    }
}

/// One round trip for the whole board: read the shared document, reconcile it with what is here,
/// move whatever files that implies, write it back if anything changed.
///
/// Read-merge-write, like the synced notes, and for the same reason: the merge is order-independent
/// and idempotent, so running this twice changes nothing the second time and two devices running it
/// in either order end up holding the same board.
///
/// It knows nothing about Drive, and nothing about Room or SwiftData either. Where the bytes come
/// from is the transport's business; turning rows into records is the caller's. What is left here
/// is the order things have to happen in, which is the part that can lose a file.
struct BoardSync {
    var transport: BoardTransport

    /// - Parameters:
    ///   - localHashes: files this device actually holds. Not everything it references — a strip
    ///     can name a photo this device has never fetched.
    ///   - readFile: the bytes for a hash, for uploading. Called only for hashes in `localHashes`.
    ///   - writeFile: hands over a downloaded file. Whether it lands in the media folder, the
    ///     library or a sketch is the caller's business, not this one's.
    func run(
        local: BoardSnapshot,
        localHashes: Set<String>,
        hasSyncedBefore: Bool,
        adoptsOnFirstSync: Bool,
        readFile: (String) throws -> Data,
        writeFile: (String, Data) throws -> Void
    ) async throws -> BoardSyncOutcome {
        let document = try await transport.loadDocument()
        let remote = snapshot(from: document)

        let stance = SyncBoardPlan.stance(
            hasSyncedBefore: hasSyncedBefore,
            remoteIsEmpty: remote.isEmpty,
            adoptsOnFirstSync: adoptsOnFirstSync
        )

        // Adopting takes the other device's board entire, and is only ever reached on a first sync
        // against a folder that actually holds one — see SyncBoardPlan.stance, which guards it.
        var merged = stance == .adopt ? remote : merge(local: local, remote: remote)
        merged.tasks = SyncBoardPlan.repair(merged.tasks, sketches: merged.sketches)
        merged = merged.normalised

        var outcome = BoardSyncOutcome(
            merged: merged,
            stance: stance,
            pushed: merged != remote.normalised,
            pulled: merged != local.normalised
        )

        let referenced = merged.referencedHashes
        let remoteHashes = try await transport.remoteHashes()

        // Files go up before the document does, and this is the one ordering that matters. A
        // document naming a file the folder hasn't got yet is a strip that arrives on the other
        // device pointing at nothing — and it would stay that way until something edited it again,
        // because a sync that changed nothing writes nothing.
        for hash in SyncFileStore.toUpload(
            referenced: referenced, remote: remoteHashes, localHashes: localHashes
        ).sorted() {
            try await transport.upload(hash: hash, data: try readFile(hash))
            outcome.uploaded.append(hash)
        }

        if outcome.pushed {
            try await transport.saveDocument(
                try SyncBoardDocument.data(
                    tasks: merged.tasks,
                    reminders: merged.reminders,
                    storage: merged.storage,
                    credentials: merged.credentials,
                    sketches: merged.sketches
                )
            )
        }

        // Only what a live record names, and only what this device hasn't got. Deliberately not
        // everything in the folder: a file no record mentions is one somebody is about to sweep.
        for hash in SyncFileStore.toDownload(referenced: referenced, localHashes: localHashes)
            .intersection(remoteHashes)
            .sorted() {
            try writeFile(hash, try await transport.download(hash: hash))
            outcome.downloaded.append(hash)
        }

        // Last, and only against the merged document — never against one device's half, where a
        // file that looks unreferenced may be the only copy of something the other device still
        // has on a strip it hasn't sent yet.
        for hash in SyncFileStore.orphans(remote: remoteHashes, referenced: referenced).sorted() {
            try await transport.deleteFile(hash: hash)
            outcome.sweptAway.append(hash)
        }

        return outcome
    }

    private func snapshot(from data: Data?) -> BoardSnapshot {
        guard let data else { return BoardSnapshot() }
        return BoardSnapshot(
            tasks: SyncBoardDocument.tasks(from: data),
            reminders: SyncBoardDocument.reminders(from: data),
            storage: SyncBoardDocument.storage(from: data),
            credentials: SyncBoardDocument.credentials(from: data),
            sketches: SyncBoardDocument.sketches(from: data)
        ).normalised
    }

    private func merge(local: BoardSnapshot, remote: BoardSnapshot) -> BoardSnapshot {
        BoardSnapshot(
            tasks: SyncBoardDocument.merge(local: local.tasks, remote: remote.tasks),
            reminders: SyncBoardDocument.merge(local: local.reminders, remote: remote.reminders),
            storage: SyncBoardDocument.merge(local: local.storage, remote: remote.storage),
            credentials: SyncBoardDocument.merge(local: local.credentials, remote: remote.credentials),
            sketches: SyncBoardDocument.merge(local: local.sketches, remote: remote.sketches)
        )
    }
}
