package com.saud.taskstrip.data

import androidx.room.Entity
import androidx.room.PrimaryKey

/** A snippet parked for reuse — pasted in from the system clipboard, shared in from another app,
 * or lifted off a strip. Kept separate from NoteEntity because the intent is different: a note is
 * a thought to act on later, a clipboard item is text you want to put somewhere else, usually
 * more than once.
 *
 * Nothing here syncs anywhere yet; [isSyncable] exists so the desktop transport that follows can
 * skip anything holding a password or token instead of that decision being retrofitted later. */
@Entity(tableName = "clipboard_items")
data class ClipboardEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val text: String,
    /** Optional short name, so a long snippet is recognisable in the list without reading it. */
    val label: String = "",
    /** Pinned items sort above the rest — for the handful reused constantly. */
    val isPinned: Boolean = false,
    /** Opt-out for the desktop sync still to come; local-only items never leave the device. */
    val isSyncable: Boolean = true,
    val createdAt: Long = System.currentTimeMillis()
)
