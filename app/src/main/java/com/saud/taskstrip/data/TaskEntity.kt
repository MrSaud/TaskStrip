package com.saud.taskstrip.data

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import java.util.UUID

@Entity(
    tableName = "tasks",
    indices = [Index(value = ["syncId"], unique = true)]
)
data class TaskEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    /** The id both devices agree on.
     *
     * The primary key above is this device's own and means nothing on the other one — which is
     * exactly why backup/restore can only overwrite: with no shared name for a row there is no
     * way to tell "the same strip, edited" from "a different strip". Minted once, never
     * regenerated, and the same shape as SyncNoteEntity's, which has worked this way already. */
    val syncId: String = UUID.randomUUID().toString(),
    /** Last edit, as milliseconds. The merge's first and strongest question: newer wins. */
    val updatedAt: Long = System.currentTimeMillis(),
    /** Kept as a tombstone so a delete can reach the other device. Dropping the row instead would
     * make a delete indistinguishable from "they haven't heard of this yet", and it would come
     * back from the dead on the next sync. */
    val isDeleted: Boolean = false,
    val title: String,
    // Superseded by `tags` — kept only so old rows/backups still map onto the table; no longer
    // read or written by the UI.
    val route: String = "",
    val notes: String = "",
    // Forces the NOTES field's layout direction regardless of the device locale — off (false)
    // means left-to-right, matching every strip before this existed.
    val notesRtl: Boolean = false,
    val priority: Priority = Priority.NORMAL,
    val dueAt: Long? = null,
    val orderIndex: Int,
    val isDone: Boolean = false,
    val isArchived: Boolean = false,
    val progress: Int = 0,
    val images: List<String> = emptyList(),
    val voiceNotes: List<String> = emptyList(),
    val documents: List<String> = emptyList(),
    val videos: List<String> = emptyList(),
    val reminderMinutesBefore: Int? = null,
    // Days until the next occurrence is spawned when this task is marked done (null = one-off).
    val repeatIntervalDays: Int? = null,
    val contacts: List<TaskContact> = emptyList(),
    val tags: List<String> = emptyList(),
    // Set the instant a strip is marked done, cleared if it's reopened — drives "done this week"
    // style rollups (standup summary, weekly digest) that plain `isDone` can't answer alone.
    val completedAt: Long? = null,
    // Id of another strip this one can't start until finished. Single blocker, not a list — keeps
    // the model and UI simple; chain multiple strips if you need a longer dependency sequence.
    val blockedByTaskId: Long? = null,
    // Delegation: who this strip is waiting on and when a follow-up reminder should fire.
    val waitingOnName: String = "",
    val waitingOnSince: Long? = null,
    val waitingOnFollowUpDays: Int? = null,
    // Folder name (SketchStorage note id) of the sketch note linked to this strip, if any.
    val linkedSketchId: String? = null,
    // Free-text activity log — each entry is stamped with the moment it was added, building up a
    // running history of what's happened on this strip over time.
    val actionLog: List<TaskActionLogEntry> = emptyList(),
    // Links attached to the strip (e.g. a URL back to an email or web page) — tap one to open it.
    val links: List<TaskLink> = emptyList(),
    val createdAt: Long = System.currentTimeMillis()
)
