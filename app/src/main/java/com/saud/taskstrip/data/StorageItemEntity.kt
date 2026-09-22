package com.saud.taskstrip.data

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import java.util.UUID

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
@Entity(
    tableName = "storage_items",
    indices = [Index(value = ["syncId"], unique = true)]
)
data class StorageItemEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    /** The id both devices agree on — see TaskEntity.syncId. */
    val syncId: String = UUID.randomUUID().toString(),
    /** Last edit, as milliseconds. The merge's first and strongest question: newer wins. */
    val updatedAt: Long = System.currentTimeMillis(),
    /** A tombstone, so a delete can reach the other device instead of looking like a row it
     * simply hasn't heard of yet. */
    val isDeleted: Boolean = false,
    val name: String,
    val path: String,
    val type: String,
    val mimeType: String = "",
    val sizeBytes: Long = 0,
    // Free-text category (e.g. "Invoice", "Contract", "Manual") used to filter the documents
    // list — blank means untagged. Deliberately not a fixed set, matching ReminderEntity.tag.
    val tag: String = "",
    // A large emoji shown beside the file name to make its tag recognisable at a glance, kept
    // independent of `tag` itself exactly as ReminderEntity.tagEmoji is.
    val tagEmoji: String = "",
    val createdAt: Long = System.currentTimeMillis()
)
