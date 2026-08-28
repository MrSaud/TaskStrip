package com.saud.taskstrip.backup

import android.content.Context
import com.saud.taskstrip.data.CredentialDao
import com.saud.taskstrip.data.CredentialEntity
import com.saud.taskstrip.data.NoteDao
import com.saud.taskstrip.data.NoteEntity
import com.saud.taskstrip.data.Priority
import com.saud.taskstrip.data.ReminderDao
import com.saud.taskstrip.data.ReminderEntity
import com.saud.taskstrip.data.StorageItemDao
import com.saud.taskstrip.data.StorageItemEntity
import com.saud.taskstrip.data.TaskActionLogEntry
import com.saud.taskstrip.data.TaskContact
import com.saud.taskstrip.data.TaskDao
import com.saud.taskstrip.data.TaskEntity
import com.saud.taskstrip.data.TaskLink
import com.saud.taskstrip.notifications.FollowUpScheduler
import com.saud.taskstrip.notifications.GeneralReminderScheduler
import com.saud.taskstrip.notifications.ReminderScheduler
import com.saud.taskstrip.security.CredentialCrypto
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.UUID
import java.util.zip.ZipEntry
import java.util.zip.ZipInputStream
import java.util.zip.ZipOutputStream

object BackupHelper {
    private const val MANIFEST_ENTRY = "backup.json"
    private const val MEDIA_PREFIX = "media/"

    fun backupFileName(): String {
        val stamp = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date())
        return "taskstrip_backup_$stamp.zip"
    }

    /** [backupPassphrase] is only used to encrypt credential passwords for portability — pass
     * null to back up everything except passwords (title/username/url/notes still included). */
    suspend fun createBackupZip(
        context: Context,
        taskDao: TaskDao,
        credentialDao: CredentialDao,
        noteDao: NoteDao,
        reminderDao: ReminderDao,
        storageItemDao: StorageItemDao,
        backupPassphrase: String?
    ): File {
        val tasks = taskDao.getAllOnce()
        val credentials = credentialDao.getAllOnce()
        val notes = noteDao.getAllOnce()
        val reminders = reminderDao.getAllOnce()
        val storageItems = storageItemDao.getAllOnce()
        val filesRoot = context.filesDir.absolutePath

        fun relative(path: String): String? {
            if (path.isBlank()) return null
            return if (path.startsWith(filesRoot)) path.removePrefix(filesRoot).trimStart('/') else null
        }

        val tasksJson = JSONArray()
        tasks.forEach { t ->
            val obj = JSONObject()
            obj.put("title", t.title)
            obj.put("route", t.route)
            obj.put("notes", t.notes)
            obj.put("notesRtl", t.notesRtl)
            obj.put("priority", t.priority.name)
            obj.put("dueAt", t.dueAt ?: JSONObject.NULL)
            obj.put("orderIndex", t.orderIndex)
            obj.put("isDone", t.isDone)
            obj.put("isArchived", t.isArchived)
            obj.put("progress", t.progress)
            obj.put("images", JSONArray(t.images.mapNotNull(::relative)))
            obj.put("voiceNotes", JSONArray(t.voiceNotes.mapNotNull(::relative)))
            obj.put("documents", JSONArray(t.documents.mapNotNull(::relative)))
            obj.put("videos", JSONArray(t.videos.mapNotNull(::relative)))
            obj.put("reminderMinutesBefore", t.reminderMinutesBefore ?: JSONObject.NULL)
            obj.put("repeatIntervalDays", t.repeatIntervalDays ?: JSONObject.NULL)
            obj.put("contacts", JSONArray(t.contacts.map { c ->
                JSONObject().apply {
                    put("name", c.name)
                    put("email", c.email)
                    put("phone", c.phone)
                }
            }))
            obj.put("tags", JSONArray(t.tags))
            obj.put("completedAt", t.completedAt ?: JSONObject.NULL)
            // Restored tasks get fresh auto-generated ids, so a raw blockedByTaskId wouldn't
            // point at the right row anymore — store the *position* of the blocking task within
            // this same array instead, and remap it back to a real id on restore.
            val blockedIndex = t.blockedByTaskId?.let { blockerId -> tasks.indexOfFirst { it.id == blockerId } }
                ?.takeIf { it >= 0 }
            obj.put("blockedByIndex", blockedIndex ?: JSONObject.NULL)
            obj.put("waitingOnName", t.waitingOnName)
            obj.put("waitingOnSince", t.waitingOnSince ?: JSONObject.NULL)
            obj.put("waitingOnFollowUpDays", t.waitingOnFollowUpDays ?: JSONObject.NULL)
            obj.put("linkedSketchId", t.linkedSketchId ?: JSONObject.NULL)
            obj.put("actionLog", JSONArray(t.actionLog.map { e ->
                JSONObject().apply {
                    put("text", e.text)
                    put("timestamp", e.timestamp)
                }
            }))
            obj.put("links", JSONArray(t.links.map { l ->
                JSONObject().apply {
                    put("url", l.url)
                    put("label", l.label)
                }
            }))
            obj.put("createdAt", t.createdAt)
            tasksJson.put(obj)
        }

        val credentialsJson = JSONArray()
        // A credential's own encryptedPassword column is Keystore-tied (device-local, doesn't
        // survive a reinstall or move to another device) so it can never go into a backup as-is.
        // When a backup passphrase is set, decrypt it here and re-encrypt with that passphrase
        // instead — a real, portable secret the user holds, not a device secret they don't.
        // Without a passphrase, the password is left out entirely rather than ever written in
        // plain text.
        credentials.forEach { c ->
            val obj = JSONObject()
            obj.put("title", c.title)
            obj.put("username", c.username)
            obj.put("url", c.url)
            obj.put("notes", c.notes)
            if (backupPassphrase != null && c.encryptedPassword.isNotBlank()) {
                val plainPassword = CredentialCrypto.decrypt(c.encryptedPassword)
                val enc = BackupCrypto.encrypt(plainPassword, backupPassphrase)
                obj.put("passwordSalt", enc.salt)
                obj.put("passwordIv", enc.iv)
                obj.put("passwordCipher", enc.cipher)
            }
            obj.put("createdAt", c.createdAt)
            credentialsJson.put(obj)
        }

        val notesJson = JSONArray()
        notes.forEach { n ->
            val obj = JSONObject()
            obj.put("text", n.text)
            obj.put("createdAt", n.createdAt)
            notesJson.put(obj)
        }

        val remindersJson = JSONArray()
        reminders.forEach { r ->
            val obj = JSONObject()
            obj.put("text", r.text)
            obj.put("description", r.description)
            obj.put("triggerAt", r.triggerAt)
            obj.put("leadMinutesBefore", r.leadMinutesBefore ?: JSONObject.NULL)
            obj.put("repeatAmount", r.repeatAmount ?: JSONObject.NULL)
            obj.put("repeatUnit", r.repeatUnit ?: JSONObject.NULL)
            obj.put("tag", r.tag)
            obj.put("tagEmoji", r.tagEmoji)
            obj.put("isDone", r.isDone)
            obj.put("createdAt", r.createdAt)
            remindersJson.put(obj)
        }

        val storageItemsJson = JSONArray()
        storageItems.forEach { s ->
            val obj = JSONObject()
            obj.put("name", s.name)
            obj.put("path", relative(s.path) ?: return@forEach)
            obj.put("type", s.type)
            obj.put("mimeType", s.mimeType)
            obj.put("sizeBytes", s.sizeBytes)
            obj.put("tag", s.tag)
            obj.put("tagEmoji", s.tagEmoji)
            obj.put("createdAt", s.createdAt)
            storageItemsJson.put(obj)
        }

        val manifest = JSONObject().apply {
            put("version", 1)
            put("tasks", tasksJson)
            put("credentials", credentialsJson)
            put("notes", notesJson)
            put("reminders", remindersJson)
            put("storageItems", storageItemsJson)
        }

        val zipFile = File(context.cacheDir, "backup_${UUID.randomUUID()}.zip")
        ZipOutputStream(zipFile.outputStream()).use { zip ->
            zip.putNextEntry(ZipEntry(MANIFEST_ENTRY))
            zip.write(manifest.toString().toByteArray())
            zip.closeEntry()

            // Sketch notes live under filesDir/sketches/<note>/ but aren't referenced by any
            // TaskEntity (they're standalone files, not a task attachment), so they need to be
            // walked separately rather than falling out of the task attachment paths below.
            // listFiles() on the sketches dir itself returns the per-note *folders*, not files —
            // has to go one level deeper to reach the actual pages/.name/.created inside each.
            val sketchPaths = (File(filesRoot, "sketches").listFiles() ?: emptyArray())
                .filter { it.isDirectory }
                .flatMap { noteDir -> noteDir.listFiles()?.toList() ?: emptyList() }
                .map { it.absolutePath }
            val allPaths = (
                tasks.flatMap { it.images + it.voiceNotes + it.documents + it.videos } +
                    sketchPaths +
                    storageItems.map { it.path }
                ).toSet()
            allPaths.forEach { path ->
                val rel = relative(path) ?: return@forEach
                val file = File(path)
                if (!file.exists()) return@forEach
                zip.putNextEntry(ZipEntry(MEDIA_PREFIX + rel))
                file.inputStream().use { it.copyTo(zip) }
                zip.closeEntry()
            }
        }
        return zipFile
    }

    /** @param credentialPasswordsRestored how many credential passwords were successfully
     * decrypted and restored.
     * @param credentialPasswordsFailed how many credentials had an encrypted password in the
     * backup that couldn't be decrypted with the passphrase given (wrong passphrase, or none
     * given) — those come back with a blank password that must be re-entered, same as before this
     * feature existed. */
    data class RestoreResult(val credentialPasswordsRestored: Int, val credentialPasswordsFailed: Int)

    /** Replaces ALL current tasks/credentials with the backup's contents. [restorePassphrase] must
     * match whatever passphrase was set when the backup was created to recover credential
     * passwords — see [RestoreResult]. */
    suspend fun restoreFromZip(
        context: Context,
        zipFile: File,
        taskDao: TaskDao,
        credentialDao: CredentialDao,
        noteDao: NoteDao,
        reminderDao: ReminderDao,
        storageItemDao: StorageItemDao,
        restorePassphrase: String?
    ): RestoreResult {
        val filesRoot = context.filesDir
        var manifest: JSONObject? = null
        ZipInputStream(zipFile.inputStream()).use { zip ->
            var entry = zip.nextEntry
            while (entry != null) {
                val name = entry.name
                if (name == MANIFEST_ENTRY) {
                    manifest = JSONObject(zip.readBytes().toString(Charsets.UTF_8))
                } else if (name.startsWith(MEDIA_PREFIX)) {
                    val relative = name.removePrefix(MEDIA_PREFIX)
                    val destination = File(filesRoot, relative)
                    destination.parentFile?.mkdirs()
                    destination.outputStream().use { out -> zip.copyTo(out) }
                }
                zip.closeEntry()
                entry = zip.nextEntry
            }
        }

        val data = manifest ?: throw IllegalStateException("Backup file is missing its manifest")

        taskDao.deleteAll()
        credentialDao.deleteAll()
        noteDao.deleteAll()
        reminderDao.deleteAll()
        storageItemDao.deleteAll()

        val tasksJson = data.getJSONArray("tasks")
        // Index (within tasksJson) of the strip each restored task is blocked by, if any — see
        // the matching comment in createBackupZip for why this is an index, not a raw id.
        val blockedByIndices = (0 until tasksJson.length()).map { i ->
            val obj = tasksJson.getJSONObject(i)
            if (obj.isNull("blockedByIndex")) null else obj.getInt("blockedByIndex")
        }
        val restoredTasks = (0 until tasksJson.length()).map { i ->
            val obj = tasksJson.getJSONObject(i)
            fun paths(key: String): List<String> {
                val arr = obj.getJSONArray(key)
                return (0 until arr.length()).map { File(filesRoot, arr.getString(it)).absolutePath }
            }
            TaskEntity(
                title = obj.getString("title"),
                route = obj.getString("route"),
                notes = obj.getString("notes"),
                notesRtl = obj.optBoolean("notesRtl", false),
                priority = Priority.valueOf(obj.getString("priority")),
                dueAt = if (obj.isNull("dueAt")) null else obj.getLong("dueAt"),
                orderIndex = obj.getInt("orderIndex"),
                isDone = obj.getBoolean("isDone"),
                isArchived = obj.getBoolean("isArchived"),
                progress = obj.getInt("progress"),
                images = paths("images"),
                voiceNotes = paths("voiceNotes"),
                documents = paths("documents"),
                videos = paths("videos"),
                reminderMinutesBefore = if (obj.isNull("reminderMinutesBefore")) null else obj.getInt("reminderMinutesBefore"),
                repeatIntervalDays = if (obj.isNull("repeatIntervalDays")) null else obj.getInt("repeatIntervalDays"),
                contacts = (obj.optJSONArray("contacts") ?: JSONArray()).let { arr ->
                    (0 until arr.length()).map { i ->
                        val c = arr.getJSONObject(i)
                        TaskContact(name = c.getString("name"), email = c.optString("email"), phone = c.optString("phone"))
                    }
                },
                tags = (obj.optJSONArray("tags") ?: JSONArray()).let { arr ->
                    (0 until arr.length()).map { i -> arr.getString(i) }
                },
                completedAt = if (obj.isNull("completedAt")) null else obj.getLong("completedAt"),
                waitingOnName = obj.optString("waitingOnName"),
                waitingOnSince = if (obj.isNull("waitingOnSince")) null else obj.getLong("waitingOnSince"),
                waitingOnFollowUpDays = if (obj.isNull("waitingOnFollowUpDays")) null else obj.getInt("waitingOnFollowUpDays"),
                linkedSketchId = if (!obj.has("linkedSketchId") || obj.isNull("linkedSketchId")) null else obj.getString("linkedSketchId"),
                actionLog = (obj.optJSONArray("actionLog") ?: JSONArray()).let { arr ->
                    (0 until arr.length()).map { i ->
                        val e = arr.getJSONObject(i)
                        TaskActionLogEntry(text = e.optString("text"), timestamp = e.optLong("timestamp"))
                    }
                },
                links = (obj.optJSONArray("links") ?: JSONArray()).let { arr ->
                    (0 until arr.length()).map { i ->
                        val l = arr.getJSONObject(i)
                        TaskLink(url = l.optString("url"), label = l.optString("label"))
                    }
                },
                createdAt = obj.getLong("createdAt")
            )
        }
        val newIds = taskDao.insertAll(restoredTasks)
        restoredTasks.forEachIndexed { index, task ->
            val blockedIndex = blockedByIndices[index] ?: return@forEachIndexed
            if (blockedIndex !in newIds.indices) return@forEachIndexed
            taskDao.update(task.copy(id = newIds[index], blockedByTaskId = newIds[blockedIndex]))
        }

        val credentialsJson = data.getJSONArray("credentials")
        var passwordsRestored = 0
        var passwordsFailed = 0
        val restoredCredentials = (0 until credentialsJson.length()).map { i ->
            val obj = credentialsJson.getJSONObject(i)
            val hasEncryptedPassword = obj.has("passwordCipher") && !obj.isNull("passwordCipher")
            val encryptedPassword = if (hasEncryptedPassword && restorePassphrase != null) {
                val enc = BackupCrypto.Encrypted(
                    salt = obj.getString("passwordSalt"),
                    iv = obj.getString("passwordIv"),
                    cipher = obj.getString("passwordCipher")
                )
                val plainPassword = BackupCrypto.decrypt(enc, restorePassphrase)
                if (plainPassword != null) {
                    passwordsRestored++
                    CredentialCrypto.encrypt(plainPassword)
                } else {
                    passwordsFailed++
                    ""
                }
            } else {
                if (hasEncryptedPassword) passwordsFailed++
                ""
            }
            CredentialEntity(
                title = obj.getString("title"),
                username = obj.getString("username"),
                encryptedPassword = encryptedPassword,
                url = obj.getString("url"),
                notes = obj.getString("notes"),
                createdAt = obj.getLong("createdAt")
            )
        }
        credentialDao.insertAll(restoredCredentials)

        val notesJson = data.optJSONArray("notes") ?: JSONArray()
        val restoredNotes = (0 until notesJson.length()).map { i ->
            val obj = notesJson.getJSONObject(i)
            NoteEntity(text = obj.getString("text"), createdAt = obj.getLong("createdAt"))
        }
        noteDao.insertAll(restoredNotes)

        val remindersJson = data.optJSONArray("reminders") ?: JSONArray()
        val restoredReminders = (0 until remindersJson.length()).map { i ->
            val obj = remindersJson.getJSONObject(i)
            ReminderEntity(
                text = obj.getString("text"),
                description = obj.optString("description"),
                triggerAt = obj.getLong("triggerAt"),
                leadMinutesBefore = if (!obj.has("leadMinutesBefore") || obj.isNull("leadMinutesBefore")) null else obj.getInt("leadMinutesBefore"),
                repeatAmount = if (!obj.has("repeatAmount") || obj.isNull("repeatAmount")) null else obj.getInt("repeatAmount"),
                repeatUnit = if (!obj.has("repeatUnit") || obj.isNull("repeatUnit")) null else obj.getString("repeatUnit"),
                tag = obj.optString("tag"),
                tagEmoji = obj.optString("tagEmoji"),
                isDone = obj.optBoolean("isDone", false),
                createdAt = obj.getLong("createdAt")
            )
        }
        reminderDao.insertAll(restoredReminders)

        val storageItemsJson = data.optJSONArray("storageItems") ?: JSONArray()
        val restoredStorageItems = (0 until storageItemsJson.length()).map { i ->
            val obj = storageItemsJson.getJSONObject(i)
            StorageItemEntity(
                name = obj.getString("name"),
                path = File(filesRoot, obj.getString("path")).absolutePath,
                type = obj.getString("type"),
                mimeType = obj.optString("mimeType"),
                sizeBytes = obj.optLong("sizeBytes"),
                tag = obj.optString("tag"),
                tagEmoji = obj.optString("tagEmoji"),
                createdAt = obj.getLong("createdAt")
            )
        }
        storageItemDao.insertAll(restoredStorageItems)

        taskDao.getAllOnce().forEach { task ->
            if (task.dueAt != null) ReminderScheduler.schedule(context, task)
            if (task.waitingOnName.isNotBlank()) FollowUpScheduler.schedule(context, task)
        }
        reminderDao.getAllOnce().forEach { reminder -> GeneralReminderScheduler.schedule(context, reminder) }

        return RestoreResult(credentialPasswordsRestored = passwordsRestored, credentialPasswordsFailed = passwordsFailed)
    }
}
