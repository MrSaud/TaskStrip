package com.saud.taskstrip.sync

import java.io.File

/** Everything one device holds, in the form that travels. */
data class BoardSnapshot(
    val tasks: List<SyncTaskRecord> = emptyList(),
    val reminders: List<SyncReminderRecord> = emptyList(),
    val storage: List<SyncStorageRecord> = emptyList(),
    val credentials: List<SyncCredentialRecord> = emptyList(),
    val sketches: List<SyncSketchRecord> = emptyList()
) {
    val isEmpty: Boolean
        get() = tasks.isEmpty() && reminders.isEmpty() && storage.isEmpty() &&
            credentials.isEmpty() && sketches.isEmpty()

    /** Every file this board still points at. */
    val referencedHashes: Set<String>
        get() = SyncBoardDocument.referencedHashes(tasks, storage, sketches)

    /** Sorted the way the document sorts, so two snapshots holding the same rows compare equal
     * whatever order they were assembled in. */
    fun normalised() = BoardSnapshot(
        tasks = SyncBoardDocument.sortedTasks(tasks),
        reminders = SyncBoardDocument.sortedReminders(reminders),
        storage = SyncBoardDocument.sortedStorage(storage),
        credentials = SyncBoardDocument.sortedCredentials(credentials),
        sketches = SyncBoardDocument.sortedSketches(sketches)
    )
}

/** What one sync did, so a screen can say something truthful rather than just "done". */
data class BoardSyncOutcome(
    val merged: BoardSnapshot = BoardSnapshot(),
    val stance: SyncStance = SyncStance.MERGE,
    val pushed: Boolean = false,
    val pulled: Boolean = false,
    val uploaded: List<String> = emptyList(),
    val downloaded: List<String> = emptyList(),
    val sweptAway: List<String> = emptyList(),
    val failure: String? = null
) {
    val summary: String
        get() = when {
            failure != null -> failure
            stance == SyncStance.ADOPT -> "Took the other device's board."
            pulled && pushed -> "Sent your changes and took theirs."
            pulled -> "Took changes from the other device."
            pushed -> "Sent your changes."
            else -> "Already up to date."
        }
}

/**
 * One round trip for the whole board: read the shared document, reconcile it with what is here,
 * move whatever files that implies, write it back if anything changed.
 *
 * Mirrors BoardSync.swift step for step. Read-merge-write, like the synced notes, because the merge
 * is order-independent and idempotent — running this twice changes nothing the second time, and two
 * devices running it in either order end up holding the same board.
 *
 * It knows nothing about Drive, and nothing about Room either. Where the bytes come from is the
 * transport's business; turning rows into records is the caller's. What is left here is the order
 * things have to happen in, which is the part that can lose a file.
 */
class BoardSync(private val transport: BoardTransport) {

    /**
     * @param localHashes files this device actually holds — not everything it references, since a
     *   strip can name a photo this device has never fetched.
     * @param readFile the bytes for a hash, for uploading. Only called for hashes in [localHashes].
     * @param writeFile hands over a downloaded file. Whether it lands in the media folder, the
     *   library or a sketch is the caller's business, not this one's.
     */
    suspend fun run(
        local: BoardSnapshot,
        localHashes: Set<String>,
        hasSyncedBefore: Boolean,
        adoptsOnFirstSync: Boolean,
        readFile: (String) -> File?,
        writeFile: (String, File) -> Unit
    ): BoardSyncOutcome {
        val document = transport.loadDocument()
        val remote = snapshotFrom(document)

        val stance = SyncBoardPlan.stance(hasSyncedBefore, remote.isEmpty, adoptsOnFirstSync)

        // Adopting takes the other device's board entire, and is only ever reached on a first sync
        // against a folder that actually holds one — see SyncBoardPlan.stance, which guards it.
        val reconciled = if (stance == SyncStance.ADOPT) remote else merge(local, remote)
        val merged = reconciled
            .copy(tasks = SyncBoardPlan.repair(reconciled.tasks, reconciled.sketches))
            .normalised()

        val pushed = merged != remote.normalised()
        val pulled = merged != local.normalised()

        val referenced = merged.referencedHashes
        val remoteHashes = transport.remoteHashes()

        // Files go up before the document does, and this is the one ordering that matters. A
        // document naming a file the folder hasn't got yet is a strip that arrives on the other
        // device pointing at nothing — and it would stay that way until something edited it again,
        // because a sync that changed nothing writes nothing.
        val uploaded = mutableListOf<String>()
        SyncFileStore.toUpload(referenced, remoteHashes, localHashes).sorted().forEach { hash ->
            val file = readFile(hash) ?: return@forEach
            if (transport.upload(hash, file)) uploaded.add(hash)
        }

        if (pushed) {
            val json = SyncBoardDocument.toJson(
                merged.tasks, merged.reminders, merged.storage, merged.credentials, merged.sketches
            )
            if (!transport.saveDocument(json)) {
                return BoardSyncOutcome(
                    merged = merged, stance = stance, pulled = pulled, uploaded = uploaded,
                    failure = "Couldn't write to Drive."
                )
            }
        }

        // Only what a live record names, and only what this device hasn't got. Deliberately not
        // everything in the folder: a file no record mentions is one somebody is about to sweep.
        val downloaded = mutableListOf<String>()
        SyncFileStore.toDownload(referenced, localHashes).intersect(remoteHashes).sorted()
            .forEach { hash ->
                val destination = File.createTempFile("sync-", null)
                if (transport.download(hash, destination)) {
                    writeFile(hash, destination)
                    downloaded.add(hash)
                }
                destination.delete()
            }

        // Last, and only against the merged document — never against one device's half, where a
        // file that looks unreferenced may be the only copy of something the other device still has
        // on a strip it hasn't sent yet.
        val swept = mutableListOf<String>()
        SyncFileStore.orphans(remoteHashes, referenced).sorted().forEach { hash ->
            if (transport.deleteFile(hash)) swept.add(hash)
        }

        return BoardSyncOutcome(
            merged = merged,
            stance = stance,
            pushed = pushed,
            pulled = pulled,
            uploaded = uploaded,
            downloaded = downloaded,
            sweptAway = swept
        )
    }

    private fun snapshotFrom(json: String?): BoardSnapshot {
        if (json == null) return BoardSnapshot()
        return BoardSnapshot(
            tasks = SyncBoardDocument.tasksFromJson(json),
            reminders = SyncBoardDocument.remindersFromJson(json),
            storage = SyncBoardDocument.storageFromJson(json),
            credentials = SyncBoardDocument.credentialsFromJson(json),
            sketches = SyncBoardDocument.sketchesFromJson(json)
        ).normalised()
    }

    private fun merge(local: BoardSnapshot, remote: BoardSnapshot) = BoardSnapshot(
        tasks = SyncBoardDocument.mergeTasks(local.tasks, remote.tasks),
        reminders = SyncBoardDocument.mergeReminders(local.reminders, remote.reminders),
        storage = SyncBoardDocument.mergeStorage(local.storage, remote.storage),
        credentials = SyncBoardDocument.mergeCredentials(local.credentials, remote.credentials),
        sketches = SyncBoardDocument.mergeSketches(local.sketches, remote.sketches)
    )
}
