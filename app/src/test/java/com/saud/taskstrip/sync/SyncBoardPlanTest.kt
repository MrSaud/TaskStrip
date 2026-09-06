package com.saud.taskstrip.sync

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Mirrors SyncBoardPlanTests.swift case for case. These are the decisions that can quietly lose a
 * strip, so both devices are held to the same ones. */
class SyncBoardPlanTest {

    private fun task(id: String, title: String = "", at: Long = 1, deleted: Boolean = false) =
        SyncTaskRecord(id = id, updatedAt = at, isDeleted = deleted, title = title)

    private fun plan(local: List<SyncTaskRecord>, merged: List<SyncTaskRecord>) =
        SyncBoardPlan.plan(local.associateBy { it.id }, merged, { it.id }, { it.isDeleted })

    // ---- Insert, update, delete ----

    @Test
    fun `a row the merge knows and this device doesn't is an insert`() {
        val result = plan(emptyList(), listOf(task("a", "New")))

        assertEquals(listOf("New"), result.insert.map { it.title })
        assertTrue(result.update.isEmpty())
        assertTrue(result.delete.isEmpty())
    }

    @Test
    fun `a row the merge changed is an update`() {
        val result = plan(listOf(task("a", "Old")), listOf(task("a", "New", at = 2)))

        assertEquals(listOf("New"), result.update.map { it.title })
        assertTrue(result.insert.isEmpty())
    }

    /** A sync that changed nothing must write nothing, or every sync churns the database and every
     * screen watching it. */
    @Test
    fun `a row that is already identical is left alone`() {
        val same = task("a", "Same")

        assertTrue(plan(listOf(same), listOf(same)).isEmpty)
    }

    @Test
    fun `a tombstone for a row this device holds is a delete`() {
        val result = plan(listOf(task("a", "Here")), listOf(task("a", at = 2, deleted = true)))

        assertEquals(listOf("a"), result.delete)
        assertTrue(result.insert.isEmpty())
    }

    /** Inserting a row purely to delete it would be work for nobody. */
    @Test
    fun `a tombstone for a row this device never had does nothing`() {
        assertTrue(plan(emptyList(), listOf(task("a", at = 2, deleted = true))).isEmpty)
    }

    // ---- First sync ----

    /**
     * The guard that matters most in this file. A first sync against an empty or unreachable
     * folder must not read "nothing" as the truth and wipe the board it was meant to protect.
     */
    @Test
    fun `adopting never happens against an empty folder`() {
        assertEquals(
            SyncStance.MERGE,
            SyncBoardPlan.stance(hasSyncedBefore = false, remoteIsEmpty = true, adoptsOnFirstSync = true)
        )
    }

    @Test
    fun `the losing device adopts once and merges from then on`() {
        assertEquals(
            SyncStance.ADOPT,
            SyncBoardPlan.stance(hasSyncedBefore = false, remoteIsEmpty = false, adoptsOnFirstSync = true)
        )
        assertEquals(
            SyncStance.MERGE,
            SyncBoardPlan.stance(hasSyncedBefore = true, remoteIsEmpty = false, adoptsOnFirstSync = true)
        )
    }

    @Test
    fun `the winning device always merges`() {
        assertEquals(
            SyncStance.MERGE,
            SyncBoardPlan.stance(hasSyncedBefore = false, remoteIsEmpty = false, adoptsOnFirstSync = false)
        )
    }

    // ---- Repairs ----

    /**
     * Left alone, the blocked strip stays blocked forever by something nobody can see or finish —
     * the board refuses to let it be marked done and never says why.
     */
    @Test
    fun `a blocker deleted on the other device stops blocking`() {
        val blocker = task("b", "Blocker", at = 2, deleted = true)
        val blocked = SyncTaskRecord(id = "a", updatedAt = 1, blockedBySyncId = "b")

        val repaired = SyncBoardPlan.clearDanglingBlockers(listOf(blocked, blocker))

        assertNull(repaired.first { it.id == "a" }.blockedBySyncId)
    }

    @Test
    fun `a blocker that is still there keeps blocking`() {
        val blocker = task("b", "Blocker")
        val blocked = SyncTaskRecord(id = "a", updatedAt = 1, blockedBySyncId = "b")

        val repaired = SyncBoardPlan.clearDanglingBlockers(listOf(blocked, blocker))

        assertEquals("b", repaired.first { it.id == "a" }.blockedBySyncId)
    }

    /**
     * Not reachable through the UI, but a merge can build it: two devices each pointing a pair of
     * strips at the other, and the winners taken separately, is enough.
     */
    @Test
    fun `a strip cannot block itself`() {
        val looped = SyncTaskRecord(id = "a", updatedAt = 1, blockedBySyncId = "a")

        assertNull(SyncBoardPlan.clearSelfBlockers(listOf(looped)).first().blockedBySyncId)
    }

    @Test
    fun `a sketch deleted on the other device stops being linked`() {
        val strip = SyncTaskRecord(id = "a", updatedAt = 1, linkedSketchSyncId = "k")
        val gone = SyncSketchRecord(id = "k", updatedAt = 2, isDeleted = true)

        val repaired = SyncBoardPlan.clearDanglingSketchLinks(listOf(strip), listOf(gone))

        assertNull(repaired.first().linkedSketchSyncId)
    }

    @Test
    fun `a sketch that is still there stays linked`() {
        val strip = SyncTaskRecord(id = "a", updatedAt = 1, linkedSketchSyncId = "k")
        val sketch = SyncSketchRecord(id = "k", updatedAt = 1)

        val repaired = SyncBoardPlan.clearDanglingSketchLinks(listOf(strip), listOf(sketch))

        assertEquals("k", repaired.first().linkedSketchSyncId)
    }

    @Test
    fun `repair applies every rule at once`() {
        val strips = listOf(
            SyncTaskRecord(id = "a", updatedAt = 1, blockedBySyncId = "a", linkedSketchSyncId = "gone"),
            SyncTaskRecord(id = "b", updatedAt = 1, blockedBySyncId = "missing")
        )

        val repaired = SyncBoardPlan.repair(strips, emptyList())

        assertNull(repaired.first { it.id == "a" }.blockedBySyncId)
        assertNull(repaired.first { it.id == "a" }.linkedSketchSyncId)
        assertNull(repaired.first { it.id == "b" }.blockedBySyncId)
    }
}
