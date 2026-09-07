package com.saud.taskstrip.sync

import com.saud.taskstrip.backup.DriveApi
import java.io.File

/**
 * Where the shared board lives, as the only thing a sync needs to know about it.
 *
 * Mirrors BoardTransport.swift. The merge doesn't care where the bytes came from — the phone
 * reaches Drive over its REST API because it has no other choice, and a Mac with Drive for desktop
 * reads the same folder straight off disk. Both write the same names into the same folder.
 *
 * Files are addressed by hash, which is what lets this stay this small. There is no "replace a
 * file", because a changed file is a different name; no conflict to report, because identical
 * content is the same name; and nothing to version.
 */
interface BoardTransport {
    /** The document, or null if the folder hasn't got one yet. Null and "unreadable" mean the same
     * thing to a merge — nothing to add — and neither may empty this device. */
    suspend fun loadDocument(): String?

    suspend fun saveDocument(json: String): Boolean

    /** Every file already in the shared folder, by hash. What the upload set is subtracted from. */
    suspend fun remoteHashes(): Set<String>

    /** Fetched to [destination]; false if it couldn't be. */
    suspend fun download(hash: String, destination: File): Boolean

    suspend fun upload(hash: String, file: File): Boolean

    /** Only ever called for a hash no live record mentions — see SyncFileStore.orphans, computed
     * against the merged document rather than one device's half. */
    suspend fun deleteFile(hash: String): Boolean
}

/**
 * The board over Drive's API.
 *
 * Holds the folder id and the ids found while listing, because Drive addresses files by an opaque
 * id rather than by name: downloading or deleting one means having listed it first, and looking
 * the same answers up twice would be round trips for something that cannot have changed in
 * between.
 *
 * DriveApi is an object rather than an interface, so there is nothing to substitute and this class
 * has no unit tests — it is thin glue over calls that already exist, and the one piece of judgement
 * in it, which names belong to this store, lives in SyncFileStore where it is tested. The Mac's
 * equivalent has tests because its client takes a transport that can be faked. Proving this half
 * means running it against a real Drive.
 */
class DriveBoardTransport(private val accessToken: String) : BoardTransport {

    private var folderId: String? = null
    private var documentId: String? = null
    private var fileIds: MutableMap<String, String> = mutableMapOf()

    private suspend fun folder(): String? {
        folderId?.let { return it }
        return DriveApi.ensureBackupFolder(accessToken)?.also { folderId = it }
    }

    override suspend fun loadDocument(): String? {
        val folder = folder() ?: return null
        val id = DriveApi.findFile(accessToken, folder, SyncBoardDocument.FILE_NAME)
        documentId = id
        return id?.let { DriveApi.downloadText(accessToken, it) }
    }

    /** Replaced in place when it is already there, so the document keeps one id across syncs —
     * delete-and-recreate would leave anything holding the old id pointing at nothing. */
    override suspend fun saveDocument(json: String): Boolean {
        val folder = folder() ?: return false
        val existing = documentId
        return if (existing != null) {
            DriveApi.replaceText(accessToken, existing, json, SyncBoardDocument.MIME_TYPE)
        } else {
            DriveApi.uploadText(
                accessToken, folder, SyncBoardDocument.FILE_NAME, json, SyncBoardDocument.MIME_TYPE
            )?.also { documentId = it } != null
        }
    }

    /** One listing of the whole folder, filtered by name. The backups and the documents share this
     * folder, so anything without the store's prefix belongs to somebody else. */
    override suspend fun remoteHashes(): Set<String> {
        val folder = folder() ?: return emptySet()
        val found = mutableMapOf<String, String>()
        DriveApi.listBackups(accessToken, folder).forEach { entry ->
            SyncFileStore.hashFromRemoteName(entry.name)?.let { found[it] = entry.id }
        }
        fileIds = found
        return found.keys
    }

    override suspend fun download(hash: String, destination: File): Boolean {
        val id = fileIds[hash] ?: return false
        return DriveApi.downloadBackup(accessToken, id, destination)
    }

    /** Skipped when the folder already has it — not an optimisation. The name is the hash of the
     * contents, so what is there already holds exactly these bytes; uploading again would spend
     * the bandwidth to change nothing and leave two Drive files with one name. */
    override suspend fun upload(hash: String, file: File): Boolean {
        val folder = folder() ?: return false
        if (fileIds.containsKey(hash)) return true
        return DriveApi.uploadBackup(accessToken, folder, file, SyncFileStore.remoteName(hash))
    }

    /** Nothing to do when it is already gone — two devices can sweep the same orphan, and the
     * second arriving to find it missing is the system working, not failing. */
    override suspend fun deleteFile(hash: String): Boolean {
        val id = fileIds[hash] ?: return true
        return DriveApi.deleteBackup(accessToken, id).also { if (it) fileIds.remove(hash) }
    }
}
