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

        applyStorage(local, outcome, pathsByHash)
        applyCredentials(local, outcome)
        applySketches(local, outcome, pathsByHash)
    }

    /**
     * A library item is only worth a row once its bytes are somewhere.
     *
     * An item whose file hasn't landed yet is skipped rather than written with an empty path — the
     * library would list something that opens nothing, and the row would then look up to date, so
     * no later sync would fix it. Skipped, it simply arrives on the sync after the bytes do.
     */
    private suspend fun applyStorage(
        local: BoardSnapshot,
        outcome: BoardSyncOutcome,
        pathsByHash: Map<String, String>
    ) {
        val dao = db.storageItemDao()
        val existing = dao.getAllForSync().associateBy { it.syncId }
        val plan = SyncBoardPlan.plan(
            local.storage.associateBy { it.id }, outcome.merged.storage, { it.id }, { it.isDeleted }
        )

        (plan.insert + plan.update).forEach { record ->
            val here = existing[record.id]
            val path = pathsByHash[record.hash]
            if (here == null && path == null) return@forEach
            val applied = BoardRecords.applyTo(here, record, pathForNew = path.orEmpty())
            if (here == null) dao.insert(applied) else dao.update(applied)
        }
        plan.delete.forEach { syncId ->
            existing[syncId]?.let { dao.update(it.copy(isDeleted = true)) }
        }
    }

    /**
     * A credential's password has to be re-encrypted before it can be stored.
     *
     * The record carries it under the user's passphrase, which is the only form that can cross
     * between devices; this device keeps it under its own keystore. With no passphrase — or a
     * record that carried no secret — the password already stored is left exactly as it is. Losing
     * a password to a sync that couldn't read it would be losing data; keeping the old one never
     * is, and the title and username still arrive.
     */
    private suspend fun applyCredentials(local: BoardSnapshot, outcome: BoardSyncOutcome) {
        val dao = db.credentialDao()
        val existing = dao.getAllForSync().associateBy { it.syncId }
        val plan = SyncBoardPlan.plan(
            local.credentials.associateBy { it.id }, outcome.merged.credentials,
            { it.id }, { it.isDeleted }
        )

        (plan.insert + plan.update).forEach { record ->
            val here = existing[record.id]
            val applied = BoardRecords.applyTo(here, record, encryptedPassword = storedPassword(record))
            if (here == null) dao.insert(applied) else dao.update(applied)
        }
        plan.delete.forEach { syncId ->
            existing[syncId]?.let { dao.update(it.copy(isDeleted = true)) }
        }
    }

    private fun storedPassword(record: SyncCredentialRecord): String? {
        val secret = passphrase ?: return null
        if (!record.hasPassword) return null
        return runCatching {
            val plain = com.saud.taskstrip.backup.BackupCrypto.decrypt(
                com.saud.taskstrip.backup.BackupCrypto.Encrypted(
                    record.passwordSalt.orEmpty(), record.passwordIv.orEmpty(),
                    record.passwordCipher.orEmpty()
                ),
                secret
            ) ?: return null
            com.saud.taskstrip.security.CredentialCrypto.encrypt(plain)
        }.getOrNull()
    }

    /**
     * A sketch's pages are written back in the record's order, not the order they arrived.
     *
     * Page numbering is a local detail — page1.png, page2.png — and the record is what says which
     * page is which. A note whose pages haven't all landed is left alone entirely rather than
     * written half-finished: half a drawing is worse than yesterday's whole one, and the next sync
     * writes it properly once the rest of the bytes are here.
     */
    private fun applySketches(
        local: BoardSnapshot,
        outcome: BoardSyncOutcome,
        pathsByHash: Map<String, String>
    ) {
        val here = local.sketches.associateBy { it.id }
        val folders = SketchStorage.listAllForSync(context).associateBy {
            SketchStorage.getOrCreateSyncId(it)
        }

        outcome.merged.sketches.forEach { record ->
            if (record == here[record.id]) return@forEach
            val folder = folders[record.id] ?: SketchStorage.noteRef(context, "note_${record.createdAt}")

            if (record.isDeleted) {
                if (SketchStorage.listPages(folder).isNotEmpty()) SketchStorage.deleteNote(folder)
                SketchStorage.setSyncId(folder, record.id)
                return@forEach
            }

            val landed = record.pages.map { pathsByHash[it] }
            if (landed.any { it == null }) return@forEach

            folder.mkdirs()
            SketchStorage.setSyncId(folder, record.id)
            SketchStorage.listPages(folder).forEach { it.delete() }
            landed.filterNotNull().forEachIndexed { index, path ->
                File(path).copyTo(File(folder, "page${index + 1}.png"), overwrite = true)
            }
            if (record.name.isNotBlank()) SketchStorage.setName(folder, record.name)
        }
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
