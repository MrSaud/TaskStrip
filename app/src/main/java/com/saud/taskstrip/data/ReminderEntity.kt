package com.saud.taskstrip.data

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import java.util.UUID

// A standalone reminder — not tied to any strip. Fires a notification at triggerAt unless it's
// already marked done.
@Entity(
    tableName = "reminders",
    indices = [Index(value = ["syncId"], unique = true)]
)
data class ReminderEntity(
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
    // Short one-line title — the field this app had before "description" existed, so it keeps
    // the name "text" to avoid a disruptive column rename.
    val text: String,
    val description: String = "",
    val triggerAt: Long,
    // Minutes to notify ahead of triggerAt — null means notify exactly at triggerAt (the
    // default, unchanged behavior). When set, this is the only alarm scheduled (mirrors how a
    // strip's due-date reminder works: one alarm at due-lead, not a separate one at due too).
    val leadMinutesBefore: Int? = null,
    // Recurrence: repeatAmount + repeatUnit ("DAILY"/"WEEKLY"/"MONTHLY"/"YEARLY") — null/null
    // means one-shot (the default, unchanged behavior). When set, GeneralReminderReceiver
    // advances triggerAt by this interval and reschedules after each firing, using calendar
    // arithmetic (not a fixed day count) so a monthly/yearly repeat doesn't drift.
    val repeatAmount: Int? = null,
    val repeatUnit: String? = null,
    // Free-text category (e.g. "Birthday", "Service", "Documents") used to filter the reminders
    // list — blank means untagged, not restricted to a fixed set so the user can invent their own.
    val tag: String = "",
    // A large emoji shown in the reminder row to represent the tag at a glance — independent of
    // `tag` itself so two reminders sharing a tag name could still use different emoji if desired.
    val tagEmoji: String = "",
    val isDone: Boolean = false,
    val createdAt: Long = System.currentTimeMillis()
)
