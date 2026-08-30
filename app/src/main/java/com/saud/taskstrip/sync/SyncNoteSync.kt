package com.saud.taskstrip.sync

import android.content.Context
import com.saud.taskstrip.backup.DriveApi
import com.saud.taskstrip.backup.DriveAuthHelper
import com.saud.taskstrip.data.AppDatabase
import com.saud.taskstrip.data.SyncNoteEntity
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** What one sync did, so the screen can say something truthful rather than just "done". */
data class SyncNoteOutcome(
    val pushed: Boolean = false,
    val pulled: Boolean = false,
    val failure: String? = null
) {
    val summary: String
        get() = when {
            failure != null -> failure
            pulled && pushed -> "Sent your changes and took theirs."
            pulled -> "Took changes from the other device."
            pushed -> "Sent your changes."
            else -> "Already up to date."
        }
}

/** One round trip: read the shared document, merge it with what's on this phone, write it back if
 * that changed anything. Mirrors SyncNoteSync.swift step for step.
 *
 * Read-merge-write rather than anything cleverer, because the merge is order-independent and
 * idempotent — running this twice in a row changes nothing the second time, and two devices
 * running it in either order end up holding the same notes. */
object SyncNoteSync {

    suspend fun run(context: Context): SyncNoteOutcome = withContext(Dispatchers.IO) {
        val account = DriveAuthHelper.signedInAccount(context)
            ?: return@withContext SyncNoteOutcome(failure = "Sign in to Google Drive first.")
        val token = DriveAuthHelper.getAccessToken(context, account)
            ?: return@withContext SyncNoteOutcome(failure = "Couldn't get a Drive token.")
        val folderId = DriveApi.ensureBackupFolder(token)
            ?: return@withContext SyncNoteOutcome(failure = "Couldn't reach the Drive folder.")

        val dao = AppDatabase.getInstance(context).syncNoteDao()
        val local = dao.getAllOnce().map { it.toRecord() }

        val fileId = DriveApi.findFile(token, folderId, SyncNoteDocument.FILE_NAME)
        val remote = fileId
            ?.let { DriveApi.downloadText(token, it) }
            ?.let { SyncNoteDocument.fromJson(it) }
            ?: emptyList()

        val merged = SyncNoteDocument.merge(local, remote)
        // Compared against what each side actually held, so "already up to date" means it, and a
        // sync that changed nothing doesn't rewrite the document for the sake of it.
        val pushed = merged != SyncNoteDocument.sorted(remote)
        val pulled = merged != SyncNoteDocument.sorted(local)

        if (pulled) {
            dao.upsertAll(merged.map { it.toEntity() })
        }

        if (pushed) {
            val json = SyncNoteDocument.toJson(merged)
            val ok = if (fileId != null) {
                DriveApi.replaceText(token, fileId, json, SyncNoteDocument.MIME_TYPE)
            } else {
                DriveApi.uploadText(
                    token, folderId, SyncNoteDocument.FILE_NAME, json, SyncNoteDocument.MIME_TYPE
                ) != null
            }
            if (!ok) return@withContext SyncNoteOutcome(pulled = pulled, failure = "Couldn't write to Drive.")
        }

        SyncNoteOutcome(pushed = pushed, pulled = pulled)
    }
}

fun SyncNoteEntity.toRecord(): SyncNoteRecord =
    SyncNoteRecord(id = id, title = title, text = text, updatedAt = updatedAt, isDeleted = isDeleted)

fun SyncNoteRecord.toEntity(): SyncNoteEntity =
    SyncNoteEntity(id = id, title = title, text = text, updatedAt = updatedAt, isDeleted = isDeleted)
