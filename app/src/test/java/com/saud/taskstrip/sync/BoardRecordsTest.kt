package com.saud.taskstrip.sync

import com.saud.taskstrip.data.Priority
import com.saud.taskstrip.data.TaskContact
import com.saud.taskstrip.data.TaskEntity
import com.saud.taskstrip.data.TaskLink
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** What survives the trip out and back, and what deliberately doesn't. */
class BoardRecordsTest {

    private fun strip() = TaskEntity(
        id = 7,
        syncId = "strip-a",
        updatedAt = 500,
        title = "Renew the hangar insurance",
        notes = "Broker wants the valuation",
        notesRtl = true,
        priority = Priority.URGENT,
        dueAt = 1_787_100_000_000,
        orderIndex = 3,
        progress = 40,
        tags = listOf("finance", "admin"),
        contacts = listOf(TaskContact("Sam", "s@example.test", "1")),
        links = listOf(TaskLink("https://example.test", "Policy")),
        createdAt = 100
    )

    @Test
    fun `a strip goes out and comes back the same`() {
        val original = strip()

        val restored = BoardRecords.applyTo(original, BoardRecords.toRecord(original))

        assertEquals(original, restored)
    }

    /** The local key is this device's own; the shared id is what travels. */
    @Test
    fun `a blocker travels as the other strip's shared id`() {
        val blocked = strip().copy(blockedByTaskId = 42)

        val record = BoardRecords.toRecord(blocked, syncIdOfTask = { if (it == 42L) "strip-b" else null })

        assertEquals("strip-b", record.blockedBySyncId)
    }

    /**
     * A blocker whose row has gone resolves to nothing rather than to a made-up id. The far side
     * would only have to clear a dangling link, and inventing one to send is worse than none.
     */
    @Test
    fun `a blocker whose row has gone travels as nothing`() {
        val blocked = strip().copy(blockedByTaskId = 42)

        assertNull(BoardRecords.toRecord(blocked, syncIdOfTask = { null }).blockedBySyncId)
    }

    @Test
    fun `an arriving blocker becomes this device's own id`() {
        val record = BoardRecords.toRecord(strip()).copy(blockedBySyncId = "strip-b")

        val applied = BoardRecords.applyTo(strip(), record, localIdOfSyncId = { if (it == "strip-b") 99L else null })

        assertEquals(99L, applied.blockedByTaskId)
    }

    /**
     * The reason folding beats rebuilding. A record names files by hash, not by where this device
     * keeps them — a strip arriving from the other machine must not lose the photos this one holds
     * for it.
     */
    @Test
    fun `arriving over an existing strip keeps this device's own files`() {
        val here = strip().copy(images = listOf("/local/photo1.jpg"), voiceNotes = listOf("/local/note.m4a"))
        val arriving = BoardRecords.toRecord(strip()).copy(title = "Renamed elsewhere", updatedAt = 900)

        val applied = BoardRecords.applyTo(here, arriving)

        assertEquals("Renamed elsewhere", applied.title)
        assertEquals(listOf("/local/photo1.jpg"), applied.images)
        assertEquals(listOf("/local/note.m4a"), applied.voiceNotes)
        // And the row stays this device's own row.
        assertEquals(7L, applied.id)
    }

    /** A strip filed here keeps the date it was filed, not the date it arrived. */
    @Test
    fun `an existing strip keeps its own filing date`() {
        val here = strip().copy(createdAt = 100)
        val arriving = BoardRecords.toRecord(strip()).copy(createdAt = 999)

        assertEquals(100, BoardRecords.applyTo(here, arriving).createdAt)
    }

    @Test
    fun `a strip this device has never seen is filed when the record says`() {
        val arriving = BoardRecords.toRecord(strip()).copy(createdAt = 999)

        assertEquals(999, BoardRecords.applyTo(null, arriving).createdAt)
    }

    /** A priority this version doesn't recognise must not take the strip down with it. */
    @Test
    fun `an unknown priority falls back rather than throwing`() {
        val arriving = BoardRecords.toRecord(strip()).copy(priority = "CATASTROPHIC")

        assertEquals(Priority.NORMAL, BoardRecords.applyTo(null, arriving).priority)
    }

    /**
     * A credential arriving with no readable secret keeps the one already stored. Null covers both
     * "carried no password" and "no passphrase to open it with", and in each case what is here is
     * worth more than nothing.
     */
    @Test
    fun `a credential with no readable password keeps the stored one`() {
        val here = com.saud.taskstrip.data.CredentialEntity(
            syncId = "cred-a", title = "Router", encryptedPassword = "keystore-ciphertext"
        )
        val arriving = BoardRecords.toRecord(here).copy(title = "Router upstairs", updatedAt = 900)

        val applied = BoardRecords.applyTo(here, arriving, encryptedPassword = null)

        assertEquals("Router upstairs", applied.title)
        assertEquals("keystore-ciphertext", applied.encryptedPassword)
    }

    /**
     * A record says where a file's bytes are by naming them, never where this device keeps them —
     * overwriting the path would leave the item listed and no longer openable.
     */
    @Test
    fun `an arriving library item leaves this device's path alone`() {
        val here = com.saud.taskstrip.data.StorageItemEntity(
            syncId = "item-a", name = "Policy.pdf", path = "/local/policy.pdf", type = "DOCUMENT"
        )
        val arriving = BoardRecords.toRecord(here, hash = "abc").copy(name = "Policy 2026.pdf", updatedAt = 900)

        val applied = BoardRecords.applyTo(here, arriving)

        assertEquals("Policy 2026.pdf", applied.name)
        assertEquals("/local/policy.pdf", applied.path)
    }
}
