package com.saud.taskstrip.data

import androidx.room.Entity
import androidx.room.PrimaryKey
import java.util.UUID

/** A text that exists on this phone and on the Mac.
 *
 * Separate from NoteEntity, the local scratchpad, and deliberately so: a quick note is a thought
 * you jot and promote or throw away on the device you jotted it on, while this is one text with
 * two windows onto it.
 *
 * The primary key is the shared UUID rather than an autoincrementing Long, because the id has to
 * mean the same thing on the Mac. */
@Entity(tableName = "sync_notes")
data class SyncNoteEntity(
    @PrimaryKey val id: String = UUID.randomUUID().toString(),
    val title: String = "",
    val text: String = "",
    val updatedAt: Long = System.currentTimeMillis(),
    /** Kept as a tombstone so the delete can reach the other device. */
    val isDeleted: Boolean = false
)
