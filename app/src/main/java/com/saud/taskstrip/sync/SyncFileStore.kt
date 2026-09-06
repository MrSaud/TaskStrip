package com.saud.taskstrip.sync

import java.io.File
import java.security.MessageDigest

/** The shared pile of files, addressed by what's inside them.
 *
 * Every file the board carries — a strip's photos and voice notes, the storage library, a sketch's
 * pages — lives remotely under one flat prefix, named by the SHA-256 of its bytes. That one choice
 * is what keeps binaries out of the merge entirely:
 *
 *  - the same photo added on both devices hashes the same, so it uploads once and neither device
 *    has to notice the other did it;
 *  - a changed file is a different name, never a second version of the same one, so "which copy
 *    wins" is a question that cannot arise;
 *  - a file is immutable once written, so an upload can never race a download;
 *  - and what to clean up is a fact about the document rather than a history to keep — anything
 *    not named by a live record is unreachable.
 *
 * Nothing here does any transferring. Deciding what should move is the same on both platforms and
 * is worth testing on its own; actually moving it belongs to the transports, which differ.
 */
object SyncFileStore {

    /** A name prefix, not a folder.
     *
     * Both devices write into the same shared folder — the phone through Drive's API, the Mac
     * through the same folder mounted in Finder — so the layout has to be one thing. A real
     * subfolder would mean teaching both Drive clients to make and find one; a prefix on the name
     * needs nothing either of them can't already do. There is nothing for a hierarchy to
     * disambiguate anyway: content addresses collide only when the content is the same. */
    const val PREFIX = "file-"

    /** Read in blocks rather than whole: a video attachment can be hundreds of megabytes, and a
     * phone that reads one into memory to hash it is a phone that stops. */
    fun hash(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { stream ->
            val buffer = ByteArray(64 * 1024)
            while (true) {
                val read = stream.read(buffer)
                if (read <= 0) break
                digest.update(buffer, 0, read)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    fun hash(bytes: ByteArray): String =
        MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }

    /** Where a hash lives in the shared folder. Must match SyncFileStore.swift exactly — the two
     * devices are writing into the same folder and have to agree on the names. */
    fun remoteName(hash: String): String = PREFIX + hash

    /** True for a name this store owns, so a sweep can tell its own files from the documents
     * sitting beside them. */
    fun isStoreName(name: String): Boolean = name.startsWith(PREFIX)

    fun hashFromRemoteName(name: String): String? =
        if (isStoreName(name)) name.removePrefix(PREFIX).takeIf { it.isNotEmpty() } else null

    /** What this device has that the shared folder doesn't. */
    fun toUpload(referenced: Set<String>, remote: Set<String>, localHashes: Set<String>): Set<String> =
        referenced.intersect(localHashes) - remote

    /** What the board points at that this device hasn't got. Deliberately not "everything remote":
     * a device shouldn't pull down a file no live record mentions just because it is there. */
    fun toDownload(referenced: Set<String>, localHashes: Set<String>): Set<String> =
        referenced - localHashes

    /** Files nothing points at any more.
     *
     * Only ever computed against a merged document, never against one device's half — a file that
     * looks unreferenced here may be the only copy of something the other device still has on a
     * strip it hasn't sent yet, and deleting on that basis would destroy it. */
    fun orphans(remote: Set<String>, referenced: Set<String>): Set<String> = remote - referenced
}
