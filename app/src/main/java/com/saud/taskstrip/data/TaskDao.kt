package com.saud.taskstrip.data

import androidx.room.Dao
import androidx.room.Delete
import androidx.room.Insert
import androidx.room.Query
import androidx.room.Update
import kotlinx.coroutines.flow.Flow

/**
 * Every query a person sees through excludes tombstones.
 *
 * A deleted strip stays as a row so the delete can reach the other device — dropping it outright
 * would make it indistinguishable from a strip that device has never heard of, and it would come
 * straight back on the next sync. That row is bookkeeping, and it must never reach the board.
 * [getAllForSync] is the one way to see them, and it is the sync's.
 */
@Dao
interface TaskDao {
    @Query("SELECT * FROM tasks WHERE isDeleted = 0 AND isArchived = 0 ORDER BY isDone ASC, orderIndex ASC")
    fun observeTasks(): Flow<List<TaskEntity>>

    @Query(
        "SELECT * FROM tasks WHERE isDeleted = 0 AND isArchived = 1 " +
            "AND (title LIKE :query OR route LIKE :query OR notes LIKE :query) " +
            "ORDER BY createdAt DESC"
    )
    fun observeArchived(query: String): Flow<List<TaskEntity>>

    @Query("SELECT * FROM tasks WHERE isDeleted = 0 AND id = :id")
    suspend fun getById(id: Long): TaskEntity?

    @Query("SELECT * FROM tasks WHERE isDeleted = 0 AND syncId = :syncId")
    suspend fun getBySyncId(syncId: String): TaskEntity?

    @Query("SELECT COALESCE(MAX(orderIndex), -1) FROM tasks WHERE isDeleted = 0")
    suspend fun maxOrderIndex(): Int

    @Query("SELECT * FROM tasks WHERE isDeleted = 0")
    suspend fun getAllOnce(): List<TaskEntity>

    /** Tombstones included — the only caller that wants them is the sync, which has to send them
     * on so the other device learns what was deleted. */
    @Query("SELECT * FROM tasks")
    suspend fun getAllForSync(): List<TaskEntity>

    @Insert
    suspend fun insert(task: TaskEntity): Long

    // Returns the generated row ids in the same order as `tasks`, so callers restoring from a
    // backup can remap old cross-task references (like blockedByTaskId) onto the fresh ids.
    @Insert
    suspend fun insertAll(tasks: List<TaskEntity>): List<Long>

    @Update
    suspend fun update(task: TaskEntity)

    @Update
    suspend fun updateAll(tasks: List<TaskEntity>)

    /** A hard delete, kept for the sync's own tombstone sweep and for restore, which rebuilds the
     * table from nothing. Everything a person does goes through TaskRepository.deleteTask, which
     * leaves a tombstone behind instead. */
    @Delete
    suspend fun delete(task: TaskEntity)

    @Query("DELETE FROM tasks")
    suspend fun deleteAll()
}
