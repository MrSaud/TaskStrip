package com.saud.taskstrip.sync

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The contract between the two apps for the board itself.
 *
 * Deliberately the same cases as SyncBoardDocumentTests.swift, asserting the same things in the
 * same order. That is the point of them: the rules are written twice, and two devices that answer
 * a merge differently disagree with each other forever. One suite per language, holding both to
 * the same statements, is the only thing that keeps a one-character divergence from shipping.
 */
class SyncBoardDocumentTest {

    private fun task(
        id: String,
        title: String = "",
        notes: String = "",
        at: Long,
        deleted: Boolean = false
    ) = SyncTaskRecord(id = id, updatedAt = at, isDeleted = deleted, title = title, notes = notes)

    private fun reminder(id: String, text: String = "", at: Long, deleted: Boolean = false) =
        SyncReminderRecord(id = id, updatedAt = at, isDeleted = deleted, text = text)

    // ---- The file ----

    @Test
    fun `a strip survives the round trip`() {
        val original = SyncTaskRecord(
            id = "a",
            updatedAt = 1_787_000_000_000,
            title = "Renew the hangar insurance",
            notes = "Broker wants the valuation",
            notesRtl = true,
            priority = "URGENT",
            dueAt = 1_787_100_000_000,
            orderIndex = 3,
            progress = 40,
            blockedBySyncId = "b",
            waitingOnName = "Broker",
            waitingOnFollowUpDays = 5,
            repeatIntervalDays = 30,
            tags = listOf("finance", "admin"),
            links = listOf(SyncLink("https://example.test", "Policy")),
            actionLog = listOf(SyncLogEntry("Chased", 12)),
            contacts = listOf(SyncContact("Sam", "s@example.test", "1")),
            attachments = listOf(SyncAttachment("abc123", "policy.pdf", "document")),
            createdAt = 1_786_000_000_000
        )

        val read = SyncBoardDocument.tasksFromJson(SyncBoardDocument.toJson(listOf(original), emptyList()))

        assertEquals(listOf(original), read)
    }

    @Test
    fun `a reminder survives the round trip`() {
        val original = SyncReminderRecord(
            id = "r",
            updatedAt = 5,
            text = "Car Maintenance",
            details = "Service due",
            triggerAt = 1_787_000_000_000,
            leadMinutesBefore = 60,
            repeatAmount = 1,
            repeatUnit = "YEARLY",
            tag = "Service",
            tagEmoji = "🔧",
            createdAt = 3
        )

        val read = SyncBoardDocument.remindersFromJson(SyncBoardDocument.toJson(emptyList(), listOf(original)))

        assertEquals(listOf(original), read)
    }

    /**
     * A missing due date must come back missing. Reading it as zero would invent 1970 as a
     * deadline and put the strip permanently overdue on the other device.
     */
    @Test
    fun `an absent date stays absent`() {
        val original = SyncTaskRecord(id = "a", updatedAt = 1, dueAt = null, completedAt = null)

        val read = SyncBoardDocument.tasksFromJson(SyncBoardDocument.toJson(listOf(original), emptyList()))

        assertNull(read.first().dueAt)
        assertNull(read.first().completedAt)
    }

    @Test
    fun `an entry with no id is dropped rather than given one`() {
        val json = """{"version":1,"tasks":[{"id":"","title":"Ghost"},{"id":"a","title":"Real"}]}"""

        assertEquals(listOf("Real"), SyncBoardDocument.tasksFromJson(json).map { it.title })
    }

    @Test
    fun `rubbish is no rows rather than a crash`() {
        assertEquals(0, SyncBoardDocument.tasksFromJson("not json").size)
        assertEquals(0, SyncBoardDocument.remindersFromJson("not json").size)
    }

    // ---- Merging ----

    @Test
    fun `the newer side wins`() {
        val merged = SyncBoardDocument.mergeTasks(
            listOf(task("a", title = "Old", at = 1)),
            listOf(task("a", title = "New", at = 2))
        )

        assertEquals(listOf("New"), merged.map { it.title })
    }

    /** A delete is a decision; a stale edit is not. */
    @Test
    fun `a delete outranks an edit stamped the same`() {
        val merged = SyncBoardDocument.mergeTasks(
            listOf(task("a", title = "Edited", at = 7)),
            listOf(task("a", at = 7, deleted = true))
        )

        assertTrue(merged.first().isDeleted)
    }

    /**
     * The whole point of the tie-breaks: both devices must land on the same side no matter which
     * order they merge in, or they hand each other opposite answers forever.
     */
    @Test
    fun `merging is order independent`() {
        val mine = listOf(task("a", title = "Alpha", at = 4), task("b", title = "Beta", at = 9))
        val theirs = listOf(task("a", title = "Alef", at = 4), task("c", title = "Gamma", at = 1))

        assertEquals(
            SyncBoardDocument.mergeTasks(mine, theirs),
            SyncBoardDocument.mergeTasks(theirs, mine)
        )
    }

    @Test
    fun `merging reminders is order independent too`() {
        val mine = listOf(reminder("a", text = "Alpha", at = 4))
        val theirs = listOf(reminder("a", text = "Alef", at = 4), reminder("b", text = "Beta", at = 2))

        assertEquals(
            SyncBoardDocument.mergeReminders(mine, theirs),
            SyncBoardDocument.mergeReminders(theirs, mine)
        )
    }

    /** Running a sync twice must change nothing the second time. */
    @Test
    fun `merging is idempotent`() {
        val mine = listOf(task("a", title = "One", at = 3))
        val theirs = listOf(task("a", title = "Two", at = 5), task("b", title = "Other", at = 1))

        val once = SyncBoardDocument.mergeTasks(mine, theirs)

        assertEquals(once, SyncBoardDocument.mergeTasks(once, theirs))
    }

    /**
     * Bytes, not Kotlin's string ordering — Kotlin orders UTF-16 code units and Swift orders
     * grapheme clusters, and a tie-break the two disagree about is worse than none.
     */
    @Test
    fun `the tie-break compares bytes`() {
        assertTrue(SyncBoardDocument.isGreater("b", "a"))
        assertFalse(SyncBoardDocument.isGreater("a", "b"))
        assertTrue(SyncBoardDocument.isGreater("ab", "a"))
        assertFalse(SyncBoardDocument.isGreater("a", "a"))
        // Arabic: the same comparison both platforms can compute the same way.
        assertTrue(SyncBoardDocument.isGreater("ب", "ا"))
    }

    // ---- Files ----

    @Test
    fun `only files a live strip points at are kept`() {
        val live = SyncTaskRecord(
            id = "a",
            updatedAt = 1,
            attachments = listOf(SyncAttachment("keep", "a.jpg", "image"))
        )
        val buried = SyncTaskRecord(
            id = "b",
            updatedAt = 1,
            isDeleted = true,
            attachments = listOf(SyncAttachment("drop", "b.jpg", "image"))
        )

        assertEquals(setOf("keep"), SyncBoardDocument.referencedHashes(listOf(live, buried)))
    }

    @Test
    fun `tombstones are bookkeeping not rows`() {
        val rows = listOf(task("a", title = "Here", at = 1), task("b", at = 1, deleted = true))

        assertEquals(listOf("Here"), SyncBoardDocument.visibleTasks(rows).map { it.title })
    }
}
