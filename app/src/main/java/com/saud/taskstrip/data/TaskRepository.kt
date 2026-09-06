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
     * updatedAt is what tells the other device this strip changed, and a write that forgets it
     * doesn't fail — it just never travels, and the change is quietly missing on the other machine
     * until something else touches the same strip. One place that always stamps is the only shape
     * of this that can't be got wrong by forgetting. */
    suspend fun updateTask(task: TaskEntity) =
        dao.update(task.copy(updatedAt = System.currentTimeMillis()))

    /** A tombstone, not a removal.
     *
     * The row has to outlive the strip long enough to tell the other device it is gone. Dropped
     * outright, a delete is indistinguishable from a strip that device has never heard of, and the
     * next sync brings it back from the dead. Every query a person sees through filters these out
     * — see TaskDao. */
    suspend fun deleteTask(task: TaskEntity) = dao.update(
        task.copy(isDeleted = true, updatedAt = System.currentTimeMillis())
    )

    /** What the sync sends: live strips and the tombstones of dead ones. */
    suspend fun getAllForSync(): List<TaskEntity> = dao.getAllForSync()

    suspend fun getBySyncId(syncId: String): TaskEntity? = dao.getBySyncId(syncId)

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
