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
            isDone = isDone
        )
        dao.update(updated)
        return updated
    }

    suspend fun delete(reminder: ReminderEntity) = dao.delete(reminder)

    suspend fun getById(id: Long): ReminderEntity? = dao.getById(id)
}
