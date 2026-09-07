package com.saud.taskstrip.sync

import android.content.Context
import com.saud.taskstrip.data.AppDatabase
import com.saud.taskstrip.media.MediaStorage
import com.saud.taskstrip.media.SketchStorage
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * The sync, wired to this device.
 *
 * [BoardSync] decides what should happen; this reads the rows to hand it and writes back what it
 * decided. The split is deliberate — everything with judgement in it is over there and tested, and
 * what is here is the database and filesystem work that only running it can prove.
 *
 * Credentials travel without their passwords unless [passphrase] is given, which is the same rule
 * the backup follows and for the same reason: the stored password is keystore-tied, dead on arrival
 * anywhere else, and the alternative to a passphrase is writing secrets in the clear.
 */
class BoardSyncRunner(
    private val context: Context,
    private val transport: BoardTransport,
    private val passphrase: String? = null
) {
    private val db = AppDatabase.getInstance(context)

    suspend fun run(
        hasSyncedBefore: Boolean,
        adoptsOnFirstSync: Boolean
    ): BoardSyncOutcome = withContext(Dispatchers.IO) {
        val tasks = db.taskDao().getAllForSync()
        val reminders = db.reminderDao().getAllForSync()
        val storage = db.storageItemDao().getAllForSync()
        val credentials = db.credentialDao().getAllForSync()
        val sketchFolders = SketchStorage.listAllForSync(context)

        // Hashed once, up front. Every later question — what to upload, what a strip's attachments
        // are called, where an arriving hash already lives — is answered from this one pass rather
        // than by reading the same files again.
        val pathsByHash = mutableMapOf<String, String>()
        fun hashed(file: File): String =
            SyncFileStore.hash(file).also { pathsByHash.putIfAbsent(it, file.path) }

        val localIdBySyncId = tasks.associate { it.syncId to it.id }
        val syncIdByLocalId = tasks.associate { it.id to it.syncId }
        val sketchSyncIdByFolder = sketchFolders.associate {
            it.name to SketchStorage.getOrCreateSyncId(it)
        }
        val sketchFolderBySyncId = sketchSyncIdByFolder.entries.associate { it.value to it.key }

        val taskRecords = tasks.map { task ->
            BoardRecords.toRecord(
                task,
                attachments = BoardFiles.attachments(task, ::hashed),
                syncIdOfTask = { syncIdByLocalId[it] },
                syncIdOfSketch = { sketchSyncIdByFolder[it] }
            )
        }
        val storageRecords = storage.map { item ->
            val file = File(item.path)
            BoardRecords.toRecord(item, hash = if (file.exists()) hashed(file) else "")
        }
        val sketchRecords = sketchFolders.map { folder ->
            SyncSketchRecord(
                id = sketchSyncIdByFolder.getValue(folder.name),
                updatedAt = if (SketchStorage.isDeleted(folder)) {
                    SketchStorage.getDeletedAt(folder)
                } else {
                    SketchStorage.lastModified(folder)
                },
                isDeleted = SketchStorage.isDeleted(folder),
                name = SketchStorage.getName(folder).orEmpty(),
                pages = SketchStorage.listPages(folder).map(::hashed),
                createdAt = SketchStorage.getCreatedAt(folder)
            )
        }

        val local = BoardSnapshot(
            tasks = taskRecords,
            reminders = reminders.map(BoardRecords::toRecord),
            storage = storageRecords,
            credentials = credentials.map { BoardRecords.toRecord(it, portablePassword(it)) },
            sketches = sketchRecords
        )

        val outcome = BoardSync(transport).run(
            local = local,
            localHashes = pathsByHash.keys.toSet(),
            hasSyncedBefore = hasSyncedBefore,
            adoptsOnFirstSync = adoptsOnFirstSync,
            readFile = { hash -> pathsByHash[hash]?.let(::File) },
            writeFile = { hash, downloaded ->
                // Landed under this device's own naming, then remembered by hash so the strips
                // applied below can find it. Where it goes depends on nothing but the kind, since
                // a file's name says nothing about which strip wanted it.
                val landed = MediaStorage.newImageFile(context).parentFile
                    ?.let { File(it, hash) }
                    ?: File(context.filesDir, hash)
                downloaded.copyTo(landed, overwrite = true)
                pathsByHash[hash] = landed.path
            }
        )

        if (outcome.failure == null) {
            applyLocally(local, outcome, localIdBySyncId, pathsByHash, sketchFolderBySyncId)
        }
        outcome
    }

    /** Only what actually differs is written — see SyncBoardPlan.plan, which is what decides that.
     * A sync that changed nothing must not touch a single row, or every sync wakes every screen. */
    private suspend fun applyLocally(
        local: BoardSnapshot,
        outcome: BoardSyncOutcome,
        localIdBySyncId: Map<String, Long>,
        pathsByHash: Map<String, String>,
        sketchFolderBySyncId: Map<String, String>
    ) {
        val taskDao = db.taskDao()
        val existingTasks = taskDao.getAllForSync().associateBy { it.syncId }
        // Planned over records on both sides, never records against rows: the plan asks whether
        // two things are equal, and an entity and a record are never equal to each other however
        // faithfully one was built from the other.
        val plan = SyncBoardPlan.plan(
            local.tasks.associateBy { it.id }, outcome.merged.tasks, { it.id }, { it.isDeleted }
        )

        (plan.insert + plan.update).forEach { record ->
            val existing = existingTasks[record.id]
            val applied = BoardRecords.applyTo(
                existing,
                record,
                localIdOfSyncId = { localIdBySyncId[it] },
                localSketchIdOf = { sketchFolderBySyncId[it] }
            )
            val withFiles = BoardFiles.applyAttachments(applied, record) { pathsByHash[it] }
            if (existing == null) taskDao.insert(withFiles) else taskDao.update(withFiles)
        }
        // A tombstone that arrived is written as a tombstone, not removed: this device has to be
        // able to tell the *next* device about the delete too.
        plan.delete.forEach { syncId ->
            existingTasks[syncId]?.let { taskDao.update(it.copy(isDeleted = true)) }
        }

        val reminderDao = db.reminderDao()
        val existingReminders = reminderDao.getAllForSync().associateBy { it.syncId }
        val reminderPlan = SyncBoardPlan.plan(
            local.reminders.associateBy { it.id }, outcome.merged.reminders, { it.id }, { it.isDeleted }
        )
        (reminderPlan.insert + reminderPlan.update).forEach { record ->
            val existing = existingReminders[record.id]
            val applied = BoardRecords.applyTo(existing, record)
            if (existing == null) reminderDao.insert(applied) else reminderDao.update(applied)
        }
        reminderPlan.delete.forEach { syncId ->
            existingReminders[syncId]?.let { reminderDao.update(it.copy(isDeleted = true)) }
        }

        // Not yet written back: the storage library, credentials and sketches.
        //
        // All three are gathered, sent and merged — they are in the document and in outcome.merged,
        // and the other device receives them — but nothing here lands them in this one's database
        // or sketch folders yet. Each needs something the strips didn't: a library item has to have
        // its bytes put somewhere before its row means anything, a credential's password has to be
        // re-encrypted under this device's keystore before it can be stored, and a sketch's pages
        // have to be written back into a folder as page1.png, page2.png in the record's order.
        //
        // Said here rather than left to be noticed: a sync that silently drops three of the five
        // things it claims to carry is worse than one that hasn't finished.
    }

    /**
     * A credential's password in a form that can leave this device, or nothing.
     *
     * The stored column is keystore-tied and means nothing anywhere else, so it is decrypted here
     * and re-encrypted under the user's passphrase — exactly what BackupHelper does. With no
     * passphrase the password simply doesn't travel; it is never written in the clear.
     */
    private fun portablePassword(
        credential: com.saud.taskstrip.data.CredentialEntity
    ): BoardRecords.PortablePassword? {
        val secret = passphrase ?: return null
        if (credential.encryptedPassword.isBlank()) return null
        return runCatching {
            val plain = com.saud.taskstrip.security.CredentialCrypto.decrypt(credential.encryptedPassword)
            val encrypted = com.saud.taskstrip.backup.BackupCrypto.encrypt(plain, secret)
            BoardRecords.PortablePassword(encrypted.salt, encrypted.iv, encrypted.cipher)
        }.getOrNull()
    }
}
