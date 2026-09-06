package com.saud.taskstrip.sync

import org.json.JSONArray
import org.json.JSONObject

/** One strip, as it travels. Fields are the ones both apps can hold; see TaskEntity and
 * TaskItem.swift, which this sits between. Attachments travel as content hashes — the bytes
 * themselves are a separate errand, so a record stays small and a photo is uploaded once however
 * many strips point at it. */
data class SyncTaskRecord(
    val id: String,
    val updatedAt: Long = 0L,
    val isDeleted: Boolean = false,
    val title: String = "",
    val notes: String = "",
    val notesRtl: Boolean = false,
    val priority: String = "NORMAL",
    val dueAt: Long? = null,
    val orderIndex: Int = 0,
    val isDone: Boolean = false,
    val isArchived: Boolean = false,
    val progress: Int = 0,
    val completedAt: Long? = null,
    /** The blocker's shared id, not its local key — the local one means nothing on the other
     * device, which is the whole reason this document exists. */
    val blockedBySyncId: String? = null,
    val waitingOnName: String = "",
    val waitingOnSince: Long? = null,
    val waitingOnFollowUpDays: Int? = null,
    val reminderMinutesBefore: Int? = null,
    val repeatIntervalDays: Int? = null,
    val tags: List<String> = emptyList(),
    val links: List<SyncLink> = emptyList(),
    val actionLog: List<SyncLogEntry> = emptyList(),
    val contacts: List<SyncContact> = emptyList(),
    val attachments: List<SyncAttachment> = emptyList(),
    val createdAt: Long = 0L
)

data class SyncReminderRecord(
    val id: String,
    val updatedAt: Long = 0L,
    val isDeleted: Boolean = false,
    val text: String = "",
    val details: String = "",
    val triggerAt: Long = 0L,
    val leadMinutesBefore: Int? = null,
    val repeatAmount: Int? = null,
    val repeatUnit: String? = null,
    val tag: String = "",
    val tagEmoji: String = "",
    val isDone: Boolean = false,
    val createdAt: Long = 0L
)

data class SyncLink(val url: String = "", val label: String = "")
data class SyncLogEntry(val text: String = "", val timestamp: Long = 0L)
data class SyncContact(val name: String = "", val email: String = "", val phone: String = "")

/** A file a strip carries, named by what's in it.
 *
 * `hash` is the SHA-256 of the bytes, which makes the name a fact about the content rather than a
 * choice either device made. Two devices that add the same photo produce the same name and upload
 * it once; a file that changes produces a different name, so a binary never has to be merged and
 * "which copy wins" never comes up. `kind` says which of a strip's lists it belongs in. */
data class SyncAttachment(val hash: String = "", val name: String = "", val kind: String = "")

/** The board both apps read and write: one JSON file beside sync_notes.json in the folder they
 * already share.
 *
 * This file is a contract with SyncBoardDocument.swift, and every rule below has to hold
 * identically there — the two devices merge the same document independently and have to reach the
 * same answer without talking to each other. It is deliberately the same design as
 * SyncNoteDocument, which has been carrying this for a while: newest wins, a delete outranks a
 * stale edit, and the tie-breaks are there so two devices holding genuinely different text stamped
 * at the same millisecond still pick the *same* side and stop disagreeing. */
object SyncBoardDocument {
    const val FILE_NAME = "sync_board.json"
    const val MIME_TYPE = "application/json"
    const val VERSION = 1

    // ---- Reading and writing ----

    fun toJson(tasks: List<SyncTaskRecord>, reminders: List<SyncReminderRecord>): String {
        val root = JSONObject()
        root.put("version", VERSION)
        root.put("tasks", JSONArray().apply { sortedTasks(tasks).forEach { put(taskToJson(it)) } })
        root.put("reminders", JSONArray().apply { sortedReminders(reminders).forEach { put(reminderToJson(it)) } })
        return root.toString(2)
    }

    /** Anything unreadable is nothing rather than an error. A corrupt or half-written document
     * must not be able to empty this device — the merge treats "no remote" as "nothing to add",
     * and the next upload writes a good document over it. */
    fun tasksFromJson(json: String): List<SyncTaskRecord> = runCatching {
        val array = JSONObject(json).optJSONArray("tasks") ?: return emptyList()
        (0 until array.length()).mapNotNull { i ->
            val obj = array.optJSONObject(i) ?: return@mapNotNull null
            val id = obj.optString("id")
            if (id.isNullOrEmpty()) return@mapNotNull null
            SyncTaskRecord(
                id = id,
                updatedAt = obj.optLong("updatedAt", 0L),
                isDeleted = obj.optBoolean("deleted", false),
                title = obj.optString("title", ""),
                notes = obj.optString("notes", ""),
                notesRtl = obj.optBoolean("notesRtl", false),
                priority = obj.optString("priority", "NORMAL").ifBlank { "NORMAL" },
                dueAt = obj.optLongOrNull("dueAt"),
                orderIndex = obj.optInt("orderIndex", 0),
                isDone = obj.optBoolean("done", false),
                isArchived = obj.optBoolean("archived", false),
                progress = obj.optInt("progress", 0),
                completedAt = obj.optLongOrNull("completedAt"),
                blockedBySyncId = obj.optStringOrNull("blockedBy"),
                waitingOnName = obj.optString("waitingOnName", ""),
                waitingOnSince = obj.optLongOrNull("waitingOnSince"),
                waitingOnFollowUpDays = obj.optIntOrNull("waitingOnFollowUpDays"),
                reminderMinutesBefore = obj.optIntOrNull("reminderMinutesBefore"),
                repeatIntervalDays = obj.optIntOrNull("repeatIntervalDays"),
                tags = obj.stringList("tags"),
                links = obj.objectList("links") { SyncLink(it.optString("url", ""), it.optString("label", "")) },
                actionLog = obj.objectList("actionLog") { SyncLogEntry(it.optString("text", ""), it.optLong("timestamp", 0L)) },
                contacts = obj.objectList("contacts") {
                    SyncContact(it.optString("name", ""), it.optString("email", ""), it.optString("phone", ""))
                },
                attachments = obj.objectList("attachments") {
                    SyncAttachment(it.optString("hash", ""), it.optString("name", ""), it.optString("kind", ""))
                },
                createdAt = obj.optLong("createdAt", 0L)
            )
        }
    }.getOrDefault(emptyList())

    fun remindersFromJson(json: String): List<SyncReminderRecord> = runCatching {
        val array = JSONObject(json).optJSONArray("reminders") ?: return emptyList()
        (0 until array.length()).mapNotNull { i ->
            val obj = array.optJSONObject(i) ?: return@mapNotNull null
            val id = obj.optString("id")
            if (id.isNullOrEmpty()) return@mapNotNull null
            SyncReminderRecord(
                id = id,
                updatedAt = obj.optLong("updatedAt", 0L),
                isDeleted = obj.optBoolean("deleted", false),
                text = obj.optString("text", ""),
                details = obj.optString("details", ""),
                triggerAt = obj.optLong("triggerAt", 0L),
                leadMinutesBefore = obj.optIntOrNull("leadMinutesBefore"),
                repeatAmount = obj.optIntOrNull("repeatAmount"),
                repeatUnit = obj.optStringOrNull("repeatUnit"),
                tag = obj.optString("tag", ""),
                tagEmoji = obj.optString("tagEmoji", ""),
                isDone = obj.optBoolean("done", false),
                createdAt = obj.optLong("createdAt", 0L)
            )
        }
    }.getOrDefault(emptyList())

    // ---- Merging ----

    fun mergeTasks(local: List<SyncTaskRecord>, remote: List<SyncTaskRecord>): List<SyncTaskRecord> {
        val byId = LinkedHashMap<String, SyncTaskRecord>()
        (local + remote).forEach { record ->
            val existing = byId[record.id]
            byId[record.id] = if (existing == null) record else winner(existing, record)
        }
        return sortedTasks(byId.values.toList())
    }

    fun mergeReminders(local: List<SyncReminderRecord>, remote: List<SyncReminderRecord>): List<SyncReminderRecord> {
        val byId = LinkedHashMap<String, SyncReminderRecord>()
        (local + remote).forEach { record ->
            val existing = byId[record.id]
            byId[record.id] = if (existing == null) record else winner(existing, record)
        }
        return sortedReminders(byId.values.toList())
    }

    /** Newer wins. Then a delete wins over a live row, because a delete is a decision and a stale
     * edit is not. Then the greater title, then the greater notes, purely so two devices holding
     * genuinely different rows stamped at the same millisecond still pick the *same* side.
     *
     * Two edits in the same millisecond that differ only past those fields keep whichever side the
     * caller had first. That is a real limit and an unreachable one in practice: it needs both
     * devices to write the same strip within the same millisecond and to agree on its title and
     * notes while disagreeing elsewhere. */
    fun winner(a: SyncTaskRecord, b: SyncTaskRecord): SyncTaskRecord {
        if (a.updatedAt != b.updatedAt) return if (a.updatedAt > b.updatedAt) a else b
        if (a.isDeleted != b.isDeleted) return if (a.isDeleted) a else b
        if (a.title != b.title) return if (isGreater(a.title, b.title)) a else b
        if (a.notes != b.notes) return if (isGreater(a.notes, b.notes)) a else b
        return a
    }

    fun winner(a: SyncReminderRecord, b: SyncReminderRecord): SyncReminderRecord {
        if (a.updatedAt != b.updatedAt) return if (a.updatedAt > b.updatedAt) a else b
        if (a.isDeleted != b.isDeleted) return if (a.isDeleted) a else b
        if (a.text != b.text) return if (isGreater(a.text, b.text)) a else b
        if (a.details != b.details) return if (isGreater(a.details, b.details)) a else b
        return a
    }

    /** Compares UTF-8 bytes, not strings — the same rule and the same reason as
     * SyncNoteDocument.isGreater: Kotlin orders UTF-16 code units and Swift orders grapheme
     * clusters, they agree for ASCII and need not for Arabic, and a tie-break the two platforms
     * disagree about is worse than no tie-break at all. */
    fun isGreater(a: String, b: String): Boolean {
        val x = a.toByteArray(Charsets.UTF_8)
        val y = b.toByteArray(Charsets.UTF_8)
        for (i in 0 until minOf(x.size, y.size)) {
            val left = x[i].toInt() and 0xFF
            val right = y[i].toInt() and 0xFF
            if (left != right) return left > right
        }
        return x.size > y.size
    }

    /** Ordered by id alone, so the file's bytes don't churn between syncs that changed nothing.
     * A strip's own orderIndex is what the board reads; this is only the document's order. */
    fun sortedTasks(tasks: List<SyncTaskRecord>): List<SyncTaskRecord> = tasks.sortedBy { it.id }

    fun sortedReminders(reminders: List<SyncReminderRecord>): List<SyncReminderRecord> =
        reminders.sortedBy { it.id }

    /** What a person should see: tombstones are bookkeeping, not rows. */
    fun visibleTasks(tasks: List<SyncTaskRecord>): List<SyncTaskRecord> = tasks.filter { !it.isDeleted }

    fun visibleReminders(reminders: List<SyncReminderRecord>): List<SyncReminderRecord> =
        reminders.filter { !it.isDeleted }

    /** Every file the board still points at. What isn't in here is an orphan and can go. */
    fun referencedHashes(tasks: List<SyncTaskRecord>): Set<String> =
        tasks.filter { !it.isDeleted }.flatMap { task -> task.attachments.map { it.hash } }
            .filter { it.isNotEmpty() }
            .toSet()

    // ---- JSON plumbing ----

    private fun taskToJson(task: SyncTaskRecord) = JSONObject().apply {
        put("id", task.id)
        put("updatedAt", task.updatedAt)
        put("deleted", task.isDeleted)
        put("title", task.title)
        put("notes", task.notes)
        put("notesRtl", task.notesRtl)
        put("priority", task.priority)
        putOrNull("dueAt", task.dueAt)
        put("orderIndex", task.orderIndex)
        put("done", task.isDone)
        put("archived", task.isArchived)
        put("progress", task.progress)
        putOrNull("completedAt", task.completedAt)
        putOrNull("blockedBy", task.blockedBySyncId)
        put("waitingOnName", task.waitingOnName)
        putOrNull("waitingOnSince", task.waitingOnSince)
        putOrNull("waitingOnFollowUpDays", task.waitingOnFollowUpDays)
        putOrNull("reminderMinutesBefore", task.reminderMinutesBefore)
        putOrNull("repeatIntervalDays", task.repeatIntervalDays)
        put("tags", JSONArray(task.tags))
        put("links", JSONArray().apply {
            task.links.forEach { put(JSONObject().put("url", it.url).put("label", it.label)) }
        })
        put("actionLog", JSONArray().apply {
            task.actionLog.forEach { put(JSONObject().put("text", it.text).put("timestamp", it.timestamp)) }
        })
        put("contacts", JSONArray().apply {
            task.contacts.forEach {
                put(JSONObject().put("name", it.name).put("email", it.email).put("phone", it.phone))
            }
        })
        put("attachments", JSONArray().apply {
            task.attachments.forEach {
                put(JSONObject().put("hash", it.hash).put("name", it.name).put("kind", it.kind))
            }
        })
        put("createdAt", task.createdAt)
    }

    private fun reminderToJson(reminder: SyncReminderRecord) = JSONObject().apply {
        put("id", reminder.id)
        put("updatedAt", reminder.updatedAt)
        put("deleted", reminder.isDeleted)
        put("text", reminder.text)
        put("details", reminder.details)
        put("triggerAt", reminder.triggerAt)
        putOrNull("leadMinutesBefore", reminder.leadMinutesBefore)
        putOrNull("repeatAmount", reminder.repeatAmount)
        putOrNull("repeatUnit", reminder.repeatUnit)
        put("tag", reminder.tag)
        put("tagEmoji", reminder.tagEmoji)
        put("done", reminder.isDone)
        put("createdAt", reminder.createdAt)
    }
}

// A null has to be written as JSON null, not left out and not turned into the string "null" —
// JSONObject.put(String, Object?) removes the key, and a reader elsewhere would then see a
// default where the writer meant "nothing".
private fun JSONObject.putOrNull(key: String, value: Any?) {
    if (value == null) put(key, JSONObject.NULL) else put(key, value)
}

private fun JSONObject.optLongOrNull(key: String): Long? =
    if (isNull(key)) null else optLong(key)

private fun JSONObject.optIntOrNull(key: String): Int? =
    if (isNull(key)) null else optInt(key)

private fun JSONObject.optStringOrNull(key: String): String? =
    if (isNull(key)) null else optString(key).ifEmpty { null }

private fun JSONObject.stringList(key: String): List<String> {
    val array = optJSONArray(key) ?: return emptyList()
    return (0 until array.length()).map { array.optString(it, "") }.filter { it.isNotEmpty() }
}

private fun <T> JSONObject.objectList(key: String, build: (JSONObject) -> T): List<T> {
    val array = optJSONArray(key) ?: return emptyList()
    return (0 until array.length()).mapNotNull { array.optJSONObject(it)?.let(build) }
}
