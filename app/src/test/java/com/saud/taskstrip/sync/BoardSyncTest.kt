package com.saud.taskstrip.sync

import java.io.File
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/**
 * The round trip, against a transport that remembers the order it was asked to do things.
 *
 * Mirrors BoardSyncTests.swift. Most of what matters here is ordering: every individual decision is
 * tested elsewhere, and what this file pins down is that they happen in the sequence that doesn't
 * lose a file.
 */
class BoardSyncTest {

    @get:Rule
    val temp = TemporaryFolder()

    /** A shared folder in memory, which also keeps a log of what it was told to do. */
    private class FakeFolder : BoardTransport {
        var document: String? = null
        val files = mutableMapOf<String, ByteArray>()
        val log = mutableListOf<String>()

        override suspend fun loadDocument(): String? = document

        override suspend fun saveDocument(json: String): Boolean {
            log.add("saveDocument")
            document = json
            return true
        }

        override suspend fun remoteHashes(): Set<String> = files.keys.toSet()

        override suspend fun download(hash: String, destination: File): Boolean {
            log.add("download $hash")
            val bytes = files[hash] ?: return false
            destination.writeBytes(bytes)
            return true
        }

        override suspend fun upload(hash: String, file: File): Boolean {
            log.add("upload $hash")
            files[hash] = file.readBytes()
            return true
        }

        override suspend fun deleteFile(hash: String): Boolean {
            log.add("delete $hash")
            files.remove(hash)
            return true
        }
    }

    private fun strip(id: String, title: String, at: Long, hashes: List<String> = emptyList()) =
        SyncTaskRecord(
            id = id,
            updatedAt = at,
            title = title,
            attachments = hashes.map { SyncAttachment(it, "$it.jpg", "image") }
        )

    private fun sync(
        folder: FakeFolder,
        local: BoardSnapshot,
        localHashes: Set<String> = emptySet(),
        hasSyncedBefore: Boolean = true,
        adopts: Boolean = false,
        received: MutableMap<String, ByteArray>? = null
    ): BoardSyncOutcome = runBlocking {
        BoardSync(folder).run(
            local = local,
            localHashes = localHashes,
            hasSyncedBefore = hasSyncedBefore,
            adoptsOnFirstSync = adopts,
            readFile = { hash -> temp.newFile("$hash-out").apply { writeBytes(hash.toByteArray()) } },
            writeFile = { hash, file -> received?.put(hash, file.readBytes()) }
        )
    }

    // ---- The round trip ----

    @Test
    fun `an empty folder takes this device's board`() {
        val folder = FakeFolder()

        val outcome = sync(folder, BoardSnapshot(tasks = listOf(strip("a", "Mine", 5))))

        assertTrue(outcome.pushed)
        assertFalse(outcome.pulled)
        assertEquals("Sent your changes.", outcome.summary)
        assertTrue(folder.document != null)
    }

    /** Running twice must change nothing the second time, or every sync rewrites the document and
     * every device re-downloads it forever. */
    @Test
    fun `a second sync with nothing new writes nothing`() {
        val folder = FakeFolder()
        sync(folder, BoardSnapshot(tasks = listOf(strip("a", "Mine", 5))))
        val settled = BoardSnapshot(tasks = SyncBoardDocument.tasksFromJson(folder.document!!))

        val outcome = sync(folder, settled)

        assertFalse(outcome.pushed)
        assertFalse(outcome.pulled)
        assertEquals("Already up to date.", outcome.summary)
    }

    @Test
    fun `the newer side wins across the round trip`() {
        val folder = FakeFolder()
        folder.document = SyncBoardDocument.toJson(listOf(strip("a", "Theirs", 9)), emptyList())

        val outcome = sync(folder, BoardSnapshot(tasks = listOf(strip("a", "Mine", 4))))

        assertEquals(listOf("Theirs"), outcome.merged.tasks.map { it.title })
        assertTrue(outcome.pulled)
    }

    // ---- Ordering, which is where a file gets lost ----

    /**
     * The ordering that matters most. A document naming a file the folder hasn't got is a strip
     * arriving on the other device pointing at nothing — and it stays that way, because a sync that
     * changes nothing writes nothing.
     */
    @Test
    fun `files go up before the document that names them`() {
        val folder = FakeFolder()
        val local = BoardSnapshot(tasks = listOf(strip("a", "With a photo", 5, listOf("photo1"))))

        sync(folder, local, localHashes = setOf("photo1"))

        assertEquals(listOf("upload photo1", "saveDocument"), folder.log)
    }

    @Test
    fun `a file the folder already has is not uploaded again`() {
        val folder = FakeFolder()
        folder.files["photo1"] = "already there".toByteArray()
        val local = BoardSnapshot(tasks = listOf(strip("a", "With a photo", 5, listOf("photo1"))))

        sync(folder, local, localHashes = setOf("photo1"))

        assertFalse(folder.log.contains("upload photo1"))
    }

    @Test
    fun `a file named by the merge and missing here is fetched`() {
        val folder = FakeFolder()
        folder.document = SyncBoardDocument.toJson(
            listOf(strip("a", "Theirs", 9, listOf("photo2"))), emptyList()
        )
        folder.files["photo2"] = "their photo".toByteArray()
        val landed = mutableMapOf<String, ByteArray>()

        val outcome = sync(folder, BoardSnapshot(), received = landed)

        assertEquals(listOf("photo2"), outcome.downloaded)
        assertEquals("their photo", landed["photo2"]!!.decodeToString())
    }

    /** Deliberately not everything in the folder: a file no record mentions is one somebody is
     * about to sweep, and pulling it down first would be work to undo. */
    @Test
    fun `a file no record names is not fetched`() {
        val folder = FakeFolder()
        folder.files["stray"] = "nobody's".toByteArray()

        val outcome = sync(folder, BoardSnapshot(tasks = listOf(strip("a", "Mine", 5))))

        assertTrue(outcome.downloaded.isEmpty())
    }

    /** Swept only against the merged board. Against one device's half, a file that looks
     * unreferenced may be the only copy of something the other still has on a strip. */
    @Test
    fun `an orphan is swept only after the merge`() {
        val folder = FakeFolder()
        folder.files["stale"] = "nothing points here".toByteArray()
        folder.document = SyncBoardDocument.toJson(listOf(strip("a", "Theirs", 9)), emptyList())

        val outcome = sync(folder, BoardSnapshot())

        assertEquals(listOf("stale"), outcome.sweptAway)
        assertNull(folder.files["stale"])
        assertEquals("delete stale", folder.log.last())
    }

    @Test
    fun `a file the other device still names is not swept`() {
        val folder = FakeFolder()
        folder.files["theirs"] = "still wanted".toByteArray()
        folder.document = SyncBoardDocument.toJson(
            listOf(strip("a", "Theirs", 9, listOf("theirs"))), emptyList()
        )

        val outcome = sync(folder, BoardSnapshot())

        assertTrue(outcome.sweptAway.isEmpty())
        assertTrue(folder.files["theirs"] != null)
    }

    // ---- The first sync ----

    @Test
    fun `adopting takes the other board entire`() {
        val folder = FakeFolder()
        folder.document = SyncBoardDocument.toJson(listOf(strip("theirs", "Phone's", 1)), emptyList())
        val mine = BoardSnapshot(tasks = listOf(strip("mine", "Mac's", 99)))

        val outcome = sync(folder, mine, hasSyncedBefore = false, adopts = true)

        assertEquals(SyncStance.ADOPT, outcome.stance)
        // Even though this device's strip is newer, it is not a merge.
        assertEquals(listOf("Phone's"), outcome.merged.tasks.map { it.title })
        assertEquals("Took the other device's board.", outcome.summary)
    }

    /** The guard that matters: a first sync against an empty folder must not read "nothing" as the
     * truth and wipe the board it was meant to protect. */
    @Test
    fun `adopting against an empty folder keeps this board`() {
        val folder = FakeFolder()
        val mine = BoardSnapshot(tasks = listOf(strip("mine", "Mine", 99)))

        val outcome = sync(folder, mine, hasSyncedBefore = false, adopts = true)

        assertEquals(SyncStance.MERGE, outcome.stance)
        assertEquals(listOf("Mine"), outcome.merged.tasks.map { it.title })
    }

    // ---- Repairs ----

    @Test
    fun `a dangling blocker is cleared on the way in`() {
        val folder = FakeFolder()
        val blocked = strip("a", "Blocked", 5).copy(blockedBySyncId = "gone")
        folder.document = SyncBoardDocument.toJson(listOf(blocked), emptyList())

        val outcome = sync(folder, BoardSnapshot())

        assertNull(outcome.merged.tasks.first().blockedBySyncId)
    }
}
