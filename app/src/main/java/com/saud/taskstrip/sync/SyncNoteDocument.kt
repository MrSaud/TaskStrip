package com.saud.taskstrip.sync

import org.json.JSONArray
import org.json.JSONObject

/** One synced text, as it travels.
 *
 * `id` is a UUID string minted once and never regenerated — it is the only thing that lets two
 * devices agree they are looking at the same note rather than at two notes that happen to say the
 * same words. Neither app's own database key is it: this one's is an autoincrementing Long and the
 * Mac's is a SwiftData object, and neither means anything on the other machine. */
data class SyncNoteRecord(
    val id: String,
    val title: String = "",
    val text: String = "",
    val updatedAt: Long = System.currentTimeMillis(),
    /** A deleted note stays in the document as a tombstone. Dropping the row instead would make a
     * delete indistinguishable from "the other device hasn't heard of this yet", and the note
     * would come back from the dead on the next sync. */
    val isDeleted: Boolean = false
) {
    /** What to call it in a list. Mirrors SyncNoteRecord.displayTitle on the Mac exactly. */
    val displayTitle: String
        get() {
            val trimmedTitle = title.trim()
            if (trimmedTitle.isNotEmpty()) return trimmedTitle
            val line = text.lineSequence().firstOrNull { it.isNotBlank() }?.trim().orEmpty()
            if (line.isEmpty()) return "Untitled"
            return if (line.length <= 80) line else line.take(80)
        }
}

/** The document both apps read and write: one JSON file in the Drive folder they already share.
 *
 * This file is a contract with SyncNoteDocument.swift. Every rule below has to hold identically
 * there, because the phone and the Mac merge the same document independently and have to reach the
 * same answer without talking to each other.
 *
 * Deliberately one file rather than one per note. What one file costs is a same-millisecond edit
 * of the same note from both devices, which loses one side — see [winner]. What it buys is one
 * download, one upload, and one atomic replacement. */
object SyncNoteDocument {
    const val FILE_NAME = "sync_notes.json"
    const val MIME_TYPE = "application/json"
    const val VERSION = 1

    // ---- Reading and writing ----

    fun toJson(notes: List<SyncNoteRecord>): String {
        val array = JSONArray()
        sorted(notes).forEach { note ->
            array.put(
                JSONObject().apply {
                    put("id", note.id)
                    put("title", note.title)
                    put("text", note.text)
                    put("updatedAt", note.updatedAt)
                    put("deleted", note.isDeleted)
                }
            )
        }
        return JSONObject().apply {
            put("version", VERSION)
            put("notes", array)
        }.toString(2)
    }

    /** Anything unreadable is no notes rather than an error. A corrupt or half-written document in
     * Drive must not be able to wipe what's on this device — the merge treats "no remote" as
     * "nothing to add", and the next upload writes a good document over it. */
    fun fromJson(json: String): List<SyncNoteRecord> = runCatching {
        val array = JSONObject(json).getJSONArray("notes")
        (0 until array.length()).mapNotNull { index ->
            val obj = array.optJSONObject(index) ?: return@mapNotNull null
            val id = obj.optString("id")
            // An entry with no id can't be merged against anything, so it's dropped rather than
            // given a fresh id and duplicated on every sync.
            if (id.isNullOrEmpty()) return@mapNotNull null
            SyncNoteRecord(
                id = id,
                title = obj.optString("title", ""),
                text = obj.optString("text", ""),
                updatedAt = obj.optLong("updatedAt", 0L),
                isDeleted = obj.optBoolean("deleted", false)
            )
        }
    }.getOrDefault(emptyList())

    // ---- Merging ----

    /** Both sides' notes, one winner per id.
     *
     * Order-independent on purpose: `merge(local, remote)` and `merge(remote, local)` produce the
     * same thing, so the phone and the Mac reach the same answer without having to agree on who
     * went first. That is what [winner]'s tie-breaks are for. */
    fun merge(local: List<SyncNoteRecord>, remote: List<SyncNoteRecord>): List<SyncNoteRecord> {
        val byId = LinkedHashMap<String, SyncNoteRecord>()
        (local + remote).forEach { note ->
            val existing = byId[note.id]
            byId[note.id] = if (existing == null) note else winner(existing, note)
        }
        return sorted(byId.values.toList())
    }

    /** Newer wins. Then a delete wins over a live note, because a delete is a decision and a stale
     * edit is not. Then the greater text, purely so that two devices holding genuinely different
     * text stamped at the same millisecond still pick the *same* side and stop disagreeing. */
    fun winner(a: SyncNoteRecord, b: SyncNoteRecord): SyncNoteRecord {
        if (a.updatedAt != b.updatedAt) return if (a.updatedAt > b.updatedAt) a else b
        if (a.isDeleted != b.isDeleted) return if (a.isDeleted) a else b
        if (a.text != b.text) return if (isGreater(a.text, b.text)) a else b
        if (a.title != b.title) return if (isGreater(a.title, b.title)) a else b
        return a
    }

    /** Compares UTF-8 bytes, not strings.
     *
     * Kotlin's `>` on a String orders UTF-16 code units; Swift's orders grapheme clusters under
     * canonical equivalence. For ASCII they agree and for Arabic they need not — and a tie-break
     * the two platforms disagree about is worse than no tie-break at all, because the devices
     * would hand each other opposite answers forever. Bytes are the one ordering both can compute
     * the same way without either having to imitate the other's string semantics. */
    fun isGreater(a: String, b: String): Boolean {
        val x = a.toByteArray(Charsets.UTF_8)
        val y = b.toByteArray(Charsets.UTF_8)
        val shared = minOf(x.size, y.size)
        for (i in 0 until shared) {
            val left = x[i].toInt() and 0xFF
            val right = y[i].toInt() and 0xFF
            if (left != right) return left > right
        }
        return x.size > y.size
    }

    /** Newest first, and by id where the times match, so the file's bytes don't churn between
     * syncs that changed nothing. */
    fun sorted(notes: List<SyncNoteRecord>): List<SyncNoteRecord> =
        notes.sortedWith(compareByDescending<SyncNoteRecord> { it.updatedAt }.thenBy { it.id })

    /** What a person should see: tombstones are bookkeeping, not notes. */
    fun visible(notes: List<SyncNoteRecord>): List<SyncNoteRecord> =
        sorted(notes.filter { !it.isDeleted })
}
