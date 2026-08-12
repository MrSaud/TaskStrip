package com.saud.taskstrip.data

import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "tasks")
data class TaskEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val title: String,
    // Superseded by `tags` — kept only so old rows/backups still map onto the table; no longer
    // read or written by the UI.
    val route: String = "",
    val notes: String = "",
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
    val createdAt: Long = System.currentTimeMillis()
)
