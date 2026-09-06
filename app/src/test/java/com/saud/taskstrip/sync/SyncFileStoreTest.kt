package com.saud.taskstrip.sync

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/** Mirrors SyncFileStoreTests.swift case for case — the two devices name files in the same shared
 * folder and have to agree, byte for byte, on what they are called. */
class SyncFileStoreTest {

    @get:Rule
    val temp = TemporaryFolder()

    /** The published SHA-256 of "abc". If this ever disagrees with the Swift suite's copy, the two
     * devices are naming the same bytes differently and every file syncs twice. */
    private val hashOfAbc = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"

    @Test
    fun `a file is named by what is inside it`() {
        val file = temp.newFile("anything.txt").apply { writeText("abc") }

        assertEquals(hashOfAbc, SyncFileStore.hash(file))
    }

    @Test
    fun `the name does not depend on the file's own name`() {
        val one = temp.newFile("photo.jpg").apply { writeText("same bytes") }
        val two = temp.newFile("copy-of-photo.jpg").apply { writeText("same bytes") }

        assertEquals(SyncFileStore.hash(one), SyncFileStore.hash(two))
    }

    /** Hashing streams rather than reading whole, because a video attachment would otherwise have
     * to fit in memory. This is bigger than the buffer, so it exercises more than one block.
     */
    @Test
    fun `a file larger than the read buffer hashes the same as its bytes`() {
        val bytes = ByteArray(200 * 1024) { (it % 251).toByte() }
        val file = temp.newFile("big.bin").apply { writeBytes(bytes) }

        assertEquals(SyncFileStore.hash(bytes), SyncFileStore.hash(file))
    }

    @Test
    fun `remote names round trip`() {
        assertEquals("file-$hashOfAbc", SyncFileStore.remoteName(hashOfAbc))
        assertEquals(hashOfAbc, SyncFileStore.hashFromRemoteName("file-$hashOfAbc"))
        assertTrue(SyncFileStore.isStoreName("file-$hashOfAbc"))
        assertFalse(SyncFileStore.isStoreName("sync_board.json"))
        assertNull(SyncFileStore.hashFromRemoteName("sync_board.json"))
        // The prefix alone names nothing.
        assertNull(SyncFileStore.hashFromRemoteName("file-"))
    }

    @Test
    fun `only files this device holds and the folder lacks are uploaded`() {
        val upload = SyncFileStore.toUpload(
            referenced = setOf("a", "b", "c"),
            remote = setOf("a"),
            localHashes = setOf("a", "b", "d")
        )

        // "c" is referenced but this device hasn't got it — that's a download, not an upload.
        // "d" is here but nothing points at it.
        assertEquals(setOf("b"), upload)
    }

    @Test
    fun `only files the board points at are downloaded`() {
        val download = SyncFileStore.toDownload(
            referenced = setOf("a", "b"),
            localHashes = setOf("a")
        )

        assertEquals(setOf("b"), download)
    }

    @Test
    fun `an orphan is a file nothing points at any more`() {
        assertEquals(
            setOf("stale"),
            SyncFileStore.orphans(remote = setOf("live", "stale"), referenced = setOf("live"))
        )
    }

    /** Two devices adding the same photo must not produce two files. */
    @Test
    fun `the same content added twice is one file`() {
        val mine = temp.newFile("mine.png").apply { writeText("identical") }
        val theirs = temp.newFile("theirs.png").apply { writeText("identical") }

        val remote = setOf(SyncFileStore.hash(mine))
        val upload = SyncFileStore.toUpload(
            referenced = setOf(SyncFileStore.hash(theirs)),
            remote = remote,
            localHashes = setOf(SyncFileStore.hash(theirs))
        )

        assertTrue(upload.isEmpty())
    }
}
