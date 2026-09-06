package com.saud.taskstrip.sync

/** What a sync should do to this device, worked out before anything is written.
 *
 * Separated from the writing on purpose. Deciding is identical on both platforms and is the part
 * that can quietly lose a strip; writing is Room here and SwiftData there and can only be checked
 * by running it. Keeping them apart means the dangerous half is the half under test.
 */
data class BoardPlan<T>(
    /** Rows the merge knows about and this device doesn't. */
    val insert: List<T> = emptyList(),
    /** Rows both sides hold where the merge picked something this device isn't already showing. */
    val update: List<T> = emptyList(),
    /** Shared ids whose rows are tombstoned and should go from this device. */
    val delete: List<String> = emptyList()
) {
    val isEmpty: Boolean get() = insert.isEmpty() && update.isEmpty() && delete.isEmpty()
}

/** How this device should treat what it finds in the shared folder. */
enum class SyncStance {
    /** The usual: reconcile both sides record by record. */
    MERGE,

    /** The other device's board is taken wholesale, replacing this one.
     *
     * Only for a first sync between two devices whose boards already overlap but were never given
     * matching ids — a merge there would union them and duplicate every row that exists on both.
     * The user names which device wins; this is what the loser does once. */
    ADOPT
}

/**
 * The decisions a sync makes before it touches the database.
 *
 * Every function here is total and takes what it needs as arguments, so the awkward cases — a
 * blocker that was deleted on the other device, a first sync against an empty folder — are things
 * a test can state rather than things that have to be reproduced with two real machines.
 */
object SyncBoardPlan {

    /**
     * Whether to reconcile or to take the other side wholesale.
     *
     * Adopting is guarded twice over: only on a device that has never synced, and only when the
     * folder actually holds a board. Without the second guard, a first sync against an empty or
     * unreachable folder would read "nothing" as the truth and wipe the board it was supposed to
     * be protecting — which is the single worst thing this feature could do.
     */
    fun stance(hasSyncedBefore: Boolean, remoteIsEmpty: Boolean, adoptsOnFirstSync: Boolean): SyncStance =
        if (!hasSyncedBefore && adoptsOnFirstSync && !remoteIsEmpty) SyncStance.ADOPT else SyncStance.MERGE

    /**
     * What to insert, update and delete, given what this device holds and what the merge decided.
     *
     * `localById` is what is on this device now, keyed by shared id; `merged` is the answer both
     * devices reached. A row identical on both sides appears in none of the three lists — a sync
     * that changed nothing must write nothing, or every sync would churn the database and every
     * screen watching it.
     */
    fun <T : Any> plan(
        localById: Map<String, T>,
        merged: List<T>,
        idOf: (T) -> String,
        isDeleted: (T) -> Boolean
    ): BoardPlan<T> {
        val insert = mutableListOf<T>()
        val update = mutableListOf<T>()
        val delete = mutableListOf<String>()

        merged.forEach { record ->
            val id = idOf(record)
            val local = localById[id]
            when {
                // A tombstone for something this device never had is not a deletion, it is
                // nothing at all — inserting it just to delete it would be work for no one.
                isDeleted(record) -> if (local != null) delete.add(id)
                local == null -> insert.add(record)
                local != record -> update.add(record)
            }
        }
        return BoardPlan(insert = insert, update = update, delete = delete)
    }

    /**
     * Strips whose blocker no longer exists, with the link cut.
     *
     * A blocker can be deleted on the other device between one sync and the next. Left alone, the
     * strip it blocked would stay blocked forever by something nobody can see or finish — the
     * board would simply refuse to let it be marked done and never say why. Room's own delete path
     * already clears these locally, for the same reason; this is that rule applied to what arrives
     * from outside.
     */
    fun clearDanglingBlockers(tasks: List<SyncTaskRecord>): List<SyncTaskRecord> {
        val alive = tasks.filter { !it.isDeleted }.map { it.id }.toSet()
        return tasks.map { task ->
            val blocker = task.blockedBySyncId
            if (blocker != null && blocker !in alive) task.copy(blockedBySyncId = null) else task
        }
    }

    /**
     * Strips whose linked sketch no longer exists, with the link cut — the same problem as a
     * dangling blocker, and left alone it opens an empty canvas or nothing at all.
     */
    fun clearDanglingSketchLinks(
        tasks: List<SyncTaskRecord>,
        sketches: List<SyncSketchRecord>
    ): List<SyncTaskRecord> {
        val alive = sketches.filter { !it.isDeleted }.map { it.id }.toSet()
        return tasks.map { task ->
            val link = task.linkedSketchSyncId
            if (link != null && link !in alive) task.copy(linkedSketchSyncId = null) else task
        }
    }

    /**
     * A strip cannot block itself.
     *
     * Not reachable through the UI, but a merge can build it: two devices each pointing a pair of
     * strips at the other, and the winners taken separately, is enough. The board would then hold
     * a strip permanently blocked by itself.
     */
    fun clearSelfBlockers(tasks: List<SyncTaskRecord>): List<SyncTaskRecord> =
        tasks.map { if (it.blockedBySyncId == it.id) it.copy(blockedBySyncId = null) else it }

    /** Every repair, in the order they have to run: self-blocks first, since clearing one can
     * leave a link that the dangling check would otherwise have kept. */
    fun repair(tasks: List<SyncTaskRecord>, sketches: List<SyncSketchRecord>): List<SyncTaskRecord> =
        clearDanglingSketchLinks(clearDanglingBlockers(clearSelfBlockers(tasks)), sketches)
}
