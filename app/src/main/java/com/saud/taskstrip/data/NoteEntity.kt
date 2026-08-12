package com.saud.taskstrip.data

import androidx.room.Entity
import androidx.room.PrimaryKey

/** A stray thought jotted with zero friction — no title, no priority, no due date. Promote it to
 * a full TaskEntity once it's actually actionable. */
@Entity(tableName = "notes")
data class NoteEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val text: String,
    val createdAt: Long = System.currentTimeMillis()
)
