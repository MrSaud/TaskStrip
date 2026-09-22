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
        links: List<TaskLink> = emptyList(),
        notesRtl: Boolean = false
    ): Long {
        val nextOrder = dao.maxOrderIndex() + 1
        return dao.insert(
            TaskEntity(
                title = title,
                route = route,
                notes = notes,
                notesRtl = notesRtl,
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
        updateTask(task.copy(contacts = task.contacts + contact))
    }

    /** Stamped here rather than by each caller.
     *
     * Kept after the board sync was removed because "when was this last changed" is worth knowing
     * on its own, and one place that always stamps is the only shape of this that can't be got
     * wrong by forgetting. Nothing reads it today. */
    suspend fun updateTask(task: TaskEntity) =
        dao.update(task.copy(updatedAt = System.currentTimeMillis()))

    /** A real delete again.
     *
     * These were tombstones while the board sync existed — a deleted row had to outlive the thing
     * so the delete could reach the other device. Nothing reads them now, and a tombstone nobody
     * collects is a row that never goes away, so the row goes.
     *
     * The isDeleted column and the queries that filter on it stay. Rows tombstoned while the sync
     * existed are deleted rows, and dropping the filter would bring every one of them back. */
    suspend fun deleteTask(task: TaskEntity) = dao.delete(task)

    suspend fun getTask(id: Long): TaskEntity? = dao.getById(id)

    suspend fun reorder(orderedTasks: List<TaskEntity>) {
        val now = System.currentTimeMillis()
        // Only the strips whose position actually moved are stamped. Reordering rewrites every
        // row's index, and stamping the lot would tell the other device that every strip on the
        // board changed — which would win every tie against edits it genuinely did make.
        val reindexed = orderedTasks.mapIndexed { index, task ->
            if (task.orderIndex == index) task else task.copy(orderIndex = index, updatedAt = now)
        }
        dao.updateAll(reindexed)
    }

    // Archiving and restoring go through updateTask rather than the dao, so they are stamped like
    // any other edit. Filing a strip away is a change the other device should see; before this
    // they were the two writes that would have quietly failed to travel.
    suspend fun archiveTask(task: TaskEntity) {
        updateTask(task.copy(isArchived = true))
    }

    suspend fun unarchiveTask(task: TaskEntity): TaskEntity {
        val nextOrder = dao.maxOrderIndex() + 1
        val restored = task.copy(isArchived = false, orderIndex = nextOrder)
        updateTask(restored)
        return restored
    }
}
