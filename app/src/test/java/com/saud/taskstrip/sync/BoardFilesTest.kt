package com.saud.taskstrip.sync

import com.saud.taskstrip.data.TaskEntity
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/** Turning a strip's four lists of paths into one list of hashes, and back. Getting this wrong
 * loses attachments quietly, which is why it is tested away from the database work. */
class BoardFilesTest {

    @get:Rule
    val temp = TemporaryFolder()

    private fun strip() = TaskEntity(syncId = "a", title = "With files", orderIndex = 0)

    @Test
    fun `every list is carried, and says which it came from`() {
        val photo = temp.newFile("photo.jpg").apply { writeText("photo") }
        val note = temp.newFile("note.m4a").apply { writeText("note") }
        val task = strip().copy(images = listOf(photo.path), voiceNotes = listOf(note.path))

        val carried = BoardFiles.attachments(task) { SyncFileStore.hash(it) }

        assertEquals(listOf(BoardFiles.IMAGE, BoardFiles.VOICE), carried.map { it.kind })
        assertEquals(listOf("photo.jpg", "note.m4a"), carried.map { it.name })
    }

    /**
     * A path with no file behind it is dropped rather than sent as a hash of nothing — naming it
     * would only ask the other device to fetch something nobody has.
     */
    @Test
    fun `a path whose file has gone is not carried`() {
        val task = strip().copy(images = listOf("/gone/missing.jpg"))

        assertTrue(BoardFiles.attachments(task) { SyncFileStore.hash(it) }.isEmpty())
    }

    @Test
    fun `arriving attachments land back in the right lists`() {
        val record = SyncTaskRecord(
            id = "a",
            attachments = listOf(
                SyncAttachment("h1", "photo.jpg", BoardFiles.IMAGE),
                SyncAttachment("h2", "doc.pdf", BoardFiles.DOCUMENT),
                SyncAttachment("h3", "clip.mp4", BoardFiles.VIDEO)
            )
        )
        val paths = mapOf("h1" to "/local/photo.jpg", "h2" to "/local/doc.pdf", "h3" to "/local/clip.mp4")

        val applied = BoardFiles.applyAttachments(strip(), record) { paths[it] }

        assertEquals(listOf("/local/photo.jpg"), applied.images)
        assertEquals(listOf("/local/doc.pdf"), applied.documents)
        assertEquals(listOf("/local/clip.mp4"), applied.videos)
        assertTrue(applied.voiceNotes.isEmpty())
    }

    /**
     * A hash this device hasn't fetched yet is left out rather than turned into a path to nothing.
     * The strip shows what it can actually open, and the next sync fills in the rest.
     */
    @Test
    fun `a hash whose bytes haven't landed is left out`() {
        val record = SyncTaskRecord(
            id = "a",
            attachments = listOf(
                SyncAttachment("here", "photo.jpg", BoardFiles.IMAGE),
                SyncAttachment("notyet", "other.jpg", BoardFiles.IMAGE)
            )
        )

        val applied = BoardFiles.applyAttachments(strip(), record) {
            if (it == "here") "/local/photo.jpg" else null
        }

        assertEquals(listOf("/local/photo.jpg"), applied.images)
    }

    /** Order follows the record, so a strip's photos stay in the order they were added rather than
     * the order this device happened to fetch them. */
    @Test
    fun `order follows the record, not this device`() {
        val record = SyncTaskRecord(
            id = "a",
            attachments = listOf(
                SyncAttachment("second", "b.jpg", BoardFiles.IMAGE),
                SyncAttachment("first", "a.jpg", BoardFiles.IMAGE)
            )
        )
        val paths = mapOf("first" to "/local/a.jpg", "second" to "/local/b.jpg")

        val applied = BoardFiles.applyAttachments(strip(), record) { paths[it] }

        assertEquals(listOf("/local/b.jpg", "/local/a.jpg"), applied.images)
    }
}
