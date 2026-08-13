package com.saud.taskstrip.data

import kotlinx.coroutines.flow.Flow

class TaskRepository(private val dao: TaskDao) {

    val tasks: Flow<List<TaskEntity>> = dao.observeTasks()

    fun observeArchivedTasks(query: String): Flow<List<TaskEntity>> = dao.observeArchived("%$query%")

    suspend fun addTask(
        title: String,
        route: String,
        notes: String,
        priority: Priority,
        dueAt: Long?,
        progress: Int,
        images: List<String>,
        voiceNotes: List<String>,
        documents: List<String>,
        videos: List<String>,
        reminderMinutesBefore: Int?,
        repeatIntervalDays: Int? = null,
        contacts: List<TaskContact> = emptyList(),
        tags: List<String> = emptyList(),
        linkedSketchId: String? = null,
        actionLog: List<TaskActionLogEntry> = emptyList(),
        links: List<TaskLink> = emptyList()
    ): Long {
        val nextOrder = dao.maxOrderIndex() + 1
        return dao.insert(
            TaskEntity(
                title = title,
                route = route,
                notes = notes,
                priority = priority,
                dueAt = dueAt,
                orderIndex = nextOrder,
                progress = progress,
                images = images,
                voiceNotes = voiceNotes,
                documents = documents,
                videos = videos,
                reminderMinutesBefore = reminderMinutesBefore,
                repeatIntervalDays = repeatIntervalDays,
                contacts = contacts,
                tags = tags,
                linkedSketchId = linkedSketchId,
                actionLog = actionLog,
                links = links
            )
        )
    }

    suspend fun addContactToTask(task: TaskEntity, contact: TaskContact) {
        dao.update(task.copy(contacts = task.contacts + contact))
    }

    suspend fun updateTask(task: TaskEntity) = dao.update(task)

    suspend fun deleteTask(task: TaskEntity) = dao.delete(task)

    suspend fun getTask(id: Long): TaskEntity? = dao.getById(id)

    suspend fun reorder(orderedTasks: List<TaskEntity>) {
        val reindexed = orderedTasks.mapIndexed { index, task -> task.copy(orderIndex = index) }
        dao.updateAll(reindexed)
    }

    suspend fun archiveTask(task: TaskEntity) {
        dao.update(task.copy(isArchived = true))
    }

    suspend fun unarchiveTask(task: TaskEntity): TaskEntity {
        val nextOrder = dao.maxOrderIndex() + 1
        val restored = task.copy(isArchived = false, orderIndex = nextOrder)
        dao.update(restored)
        return restored
    }
}
