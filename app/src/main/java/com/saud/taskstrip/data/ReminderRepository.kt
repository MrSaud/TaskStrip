package com.saud.taskstrip.data

import kotlinx.coroutines.flow.Flow

class ReminderRepository(private val dao: ReminderDao) {

    val reminders: Flow<List<ReminderEntity>> = dao.observeAll()

    suspend fun add(
        text: String,
        description: String,
        triggerAt: Long,
        leadMinutesBefore: Int?,
        repeatAmount: Int?,
        repeatUnit: String?,
        tag: String,
        tagEmoji: String
    ): ReminderEntity {
        val entity = ReminderEntity(
            text = text,
            description = description,
            triggerAt = triggerAt,
            leadMinutesBefore = leadMinutesBefore,
            repeatAmount = repeatAmount,
            repeatUnit = repeatUnit,
            tag = tag,
            tagEmoji = tagEmoji
        )
        val id = dao.insert(entity)
        return entity.copy(id = id)
    }

    suspend fun update(
        existing: ReminderEntity,
        text: String,
        description: String,
        triggerAt: Long,
        leadMinutesBefore: Int?,
        repeatAmount: Int?,
        repeatUnit: String?,
        tag: String,
        tagEmoji: String,
        isDone: Boolean
    ): ReminderEntity {
        val updated = existing.copy(
            text = text,
            description = description,
            triggerAt = triggerAt,
            leadMinutesBefore = leadMinutesBefore,
            repeatAmount = repeatAmount,
            repeatUnit = repeatUnit,
            tag = tag,
            tagEmoji = tagEmoji,
            isDone = isDone,
            // Stamped here for the same reason TaskRepository.updateTask stamps: a write that
            // forgets it doesn't fail, it just never reaches the other device.
            updatedAt = System.currentTimeMillis()
        )
        dao.update(updated)
        return updated
    }

    /** A tombstone, not a removal — see TaskRepository.deleteTask. */
    suspend fun delete(reminder: ReminderEntity) = dao.update(
        reminder.copy(isDeleted = true, updatedAt = System.currentTimeMillis())
    )

    /** What the sync sends: live reminders and the tombstones of dead ones. */
    suspend fun getAllForSync(): List<ReminderEntity> = dao.getAllForSync()

    suspend fun getById(id: Long): ReminderEntity? = dao.getById(id)
}
