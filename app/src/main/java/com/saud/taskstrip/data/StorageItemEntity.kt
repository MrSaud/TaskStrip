package com.saud.taskstrip.data

import androidx.room.Entity
import androidx.room.PrimaryKey

// The "type" values this app writes/reads — kept as a plain String column (not a Room enum
// converter) to match the lighter-weight convention already used for ReminderEntity.repeatUnit.
object StorageItemType {
    const val IMAGE = "IMAGE"
    const val VIDEO = "VIDEO"
    const val DOCUMENT = "DOCUMENT"
}

// A file dropped into the app's shared library — either shared in from another app, or added
// directly here — that any strip can later pull a copy of into its own attachments. The physical
// file lives in the same images/videos/documents directories strips already use (see
// MediaStorage), so this row is just the library's index over a subset of those files.
@Entity(tableName = "storage_items")
data class StorageItemEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val name: String,
    val path: String,
    val type: String,
    val mimeType: String = "",
    val sizeBytes: Long = 0,
    val createdAt: Long = System.currentTimeMillis()
)
