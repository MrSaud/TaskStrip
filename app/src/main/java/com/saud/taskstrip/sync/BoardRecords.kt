package com.saud.taskstrip.sync

import com.saud.taskstrip.data.CredentialEntity
import com.saud.taskstrip.data.Priority
import com.saud.taskstrip.data.ReminderEntity
import com.saud.taskstrip.data.StorageItemEntity
import com.saud.taskstrip.data.TaskActionLogEntry
import com.saud.taskstrip.data.TaskContact
import com.saud.taskstrip.data.TaskEntity
import com.saud.taskstrip.data.TaskLink

/**
 * Rows in, records out, and back again.
 *
 * The one place that knows both shapes. Everything either side of it is deliberately ignorant: the
 * document knows nothing about Room, and Room knows nothing about the document, so neither can
 * drift into depending on the other's incidental details.
 *
 * Two translations happen here and nowhere else, and both exist because a local key means nothing
 * on the other device: a blocker travels as the blocking strip's shared id, and a linked sketch as
 * the sketch's. Turning those back into local ids needs a lookup the caller holds, which is why
 * they are parameters rather than something this file goes and fetches.
 */
object BoardRecords {

    // ---- Out: what this device sends ----

    /**
     * @param attachmentsOf hashes for this strip's files, worked out by the caller — hashing is
     *   IO and slow, and the caller is the one that knows whether it already did it.
     * @param syncIdOfTask maps a local blocker id to its shared one. A blocker whose row has since
     *   gone resolves to null rather than to a made-up id: the far side would only have to clear a
     *   dangling link, and inventing one to send is worse than sending none.
     */
    fun toRecord(
        task: TaskEntity,
        attachments: List<SyncAttachment> = emptyList(),
        syncIdOfTask: (Long) -> String? = { null },
        syncIdOfSketch: (String) -> String? = { null }
    ) = SyncTaskRecord(
        id = task.syncId,
        updatedAt = task.updatedAt,
        isDeleted = task.isDeleted,
        title = task.title,
        notes = task.notes,
        notesRtl = task.notesRtl,
        priority = task.priority.name,
        dueAt = task.dueAt,
        orderIndex = task.orderIndex,
        isDone = task.isDone,
        isArchived = task.isArchived,
        progress = task.progress,
        completedAt = task.completedAt,
        blockedBySyncId = task.blockedByTaskId?.let(syncIdOfTask),
        waitingOnName = task.waitingOnName,
        waitingOnSince = task.waitingOnSince,
        waitingOnFollowUpDays = task.waitingOnFollowUpDays,
        reminderMinutesBefore = task.reminderMinutesBefore,
        repeatIntervalDays = task.repeatIntervalDays,
        linkedSketchSyncId = task.linkedSketchId?.let(syncIdOfSketch),
        tags = task.tags,
        links = task.links.map { SyncLink(it.url, it.label) },
        actionLog = task.actionLog.map { SyncLogEntry(it.text, it.timestamp) },
        contacts = task.contacts.map { SyncContact(it.name, it.email, it.phone) },
        attachments = attachments,
        createdAt = task.createdAt
    )

    fun toRecord(reminder: ReminderEntity) = SyncReminderRecord(
        id = reminder.syncId,
        updatedAt = reminder.updatedAt,
        isDeleted = reminder.isDeleted,
        text = reminder.text,
        details = reminder.description,
        triggerAt = reminder.triggerAt,
        leadMinutesBefore = reminder.leadMinutesBefore,
        repeatAmount = reminder.repeatAmount,
        repeatUnit = reminder.repeatUnit,
        tag = reminder.tag,
        tagEmoji = reminder.tagEmoji,
        isDone = reminder.isDone,
        createdAt = reminder.createdAt
    )

    fun toRecord(item: StorageItemEntity, hash: String) = SyncStorageRecord(
        id = item.syncId,
        updatedAt = item.updatedAt,
        isDeleted = item.isDeleted,
        name = item.name,
        type = item.type,
        mimeType = item.mimeType,
        sizeBytes = item.sizeBytes,
        tag = item.tag,
        tagEmoji = item.tagEmoji,
        hash = hash,
        createdAt = item.createdAt
    )

    /**
     * @param password the ciphertext under the user's passphrase, or null when there isn't one.
     *   Never the stored column: that is keystore-tied, dead on arrival anywhere else, and never
     *   the plaintext either. A credential with no passphrase travels without its secret.
     */
    fun toRecord(credential: CredentialEntity, password: PortablePassword? = null) = SyncCredentialRecord(
        id = credential.syncId,
        updatedAt = credential.updatedAt,
        isDeleted = credential.isDeleted,
        title = credential.title,
        username = credential.username,
        url = credential.url,
        notes = credential.notes,
        passwordSalt = password?.salt,
        passwordIv = password?.iv,
        passwordCipher = password?.cipher,
        createdAt = credential.createdAt
    )

    /** The three parts BackupCrypto already produces. Named so this file doesn't depend on it. */
    data class PortablePassword(val salt: String, val iv: String, val cipher: String)

    // ---- In: what arrives, folded onto what is here ----

    /**
     * The record written over an existing row, or onto a fresh one.
     *
     * `existing` is what this device holds under the same shared id, and everything the record
     * does not carry is taken from it — a local file path, this device's own key. That is the
     * point of folding rather than rebuilding: a strip that arrives from the other device must not
     * lose the photos this one has for it just because the record only named their hashes.
     */
    fun applyTo(
        existing: TaskEntity?,
        record: SyncTaskRecord,
        localIdOfSyncId: (String) -> Long? = { null },
        localSketchIdOf: (String) -> String? = { null }
    ): TaskEntity {
        val base = existing ?: TaskEntity(title = "", orderIndex = record.orderIndex)
        return base.copy(
            syncId = record.id,
            updatedAt = record.updatedAt,
            isDeleted = record.isDeleted,
            title = record.title,
            notes = record.notes,
            notesRtl = record.notesRtl,
            priority = runCatching { Priority.valueOf(record.priority) }.getOrDefault(Priority.NORMAL),
            dueAt = record.dueAt,
            orderIndex = record.orderIndex,
            isDone = record.isDone,
            isArchived = record.isArchived,
            progress = record.progress,
            completedAt = record.completedAt,
            blockedByTaskId = record.blockedBySyncId?.let(localIdOfSyncId),
            waitingOnName = record.waitingOnName,
            waitingOnSince = record.waitingOnSince,
            waitingOnFollowUpDays = record.waitingOnFollowUpDays,
            reminderMinutesBefore = record.reminderMinutesBefore,
            repeatIntervalDays = record.repeatIntervalDays,
            linkedSketchId = record.linkedSketchSyncId?.let(localSketchIdOf),
            tags = record.tags,
            links = record.links.map { TaskLink(it.url, it.label) },
            actionLog = record.actionLog.map { TaskActionLogEntry(it.text, it.timestamp) },
            contacts = record.contacts.map { TaskContact(it.name, it.email, it.phone) },
            createdAt = if (existing == null) record.createdAt else base.createdAt
        )
    }

    fun applyTo(existing: ReminderEntity?, record: SyncReminderRecord): ReminderEntity {
        val base = existing ?: ReminderEntity(text = "", triggerAt = record.triggerAt)
        return base.copy(
            syncId = record.id,
            updatedAt = record.updatedAt,
            isDeleted = record.isDeleted,
            text = record.text,
            description = record.details,
            triggerAt = record.triggerAt,
            leadMinutesBefore = record.leadMinutesBefore,
            repeatAmount = record.repeatAmount,
            repeatUnit = record.repeatUnit,
            tag = record.tag,
            tagEmoji = record.tagEmoji,
            isDone = record.isDone,
            createdAt = if (existing == null) record.createdAt else base.createdAt
        )
    }

    /**
     * The path is left alone on purpose.
     *
     * A record names a file by its hash, not by where this device keeps it. Folding a record onto
     * an existing item must not overwrite the local path with anything, or the item would still be
     * listed and no longer open. For a new item the caller supplies the path once it has actually
     * fetched the bytes.
     */
    fun applyTo(existing: StorageItemEntity?, record: SyncStorageRecord, pathForNew: String = ""): StorageItemEntity {
        val base = existing ?: StorageItemEntity(name = "", path = pathForNew, type = record.type)
        return base.copy(
            syncId = record.id,
            updatedAt = record.updatedAt,
            isDeleted = record.isDeleted,
            name = record.name,
            type = record.type,
            mimeType = record.mimeType,
            sizeBytes = record.sizeBytes,
            tag = record.tag,
            tagEmoji = record.tagEmoji,
            createdAt = if (existing == null) record.createdAt else base.createdAt
        )
    }

    /**
     * @param encryptedPassword this device's own encryption of the arriving password, or null to
     *   keep whatever is already stored. Null covers both "the record carried no secret" and "there
     *   is no passphrase to open it with", and in each case the existing password is worth more
     *   than nothing.
     */
    fun applyTo(
        existing: CredentialEntity?,
        record: SyncCredentialRecord,
        encryptedPassword: String? = null
    ): CredentialEntity {
        val base = existing ?: CredentialEntity(title = "")
        return base.copy(
            syncId = record.id,
            updatedAt = record.updatedAt,
            isDeleted = record.isDeleted,
            title = record.title,
            username = record.username,
            url = record.url,
            notes = record.notes,
            encryptedPassword = encryptedPassword ?: base.encryptedPassword,
            createdAt = if (existing == null) record.createdAt else base.createdAt
        )
    }
}
