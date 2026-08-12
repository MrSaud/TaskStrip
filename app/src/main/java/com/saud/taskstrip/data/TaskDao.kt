package com.saud.taskstrip.data

import androidx.room.Dao
import androidx.room.Delete
import androidx.room.Insert
import androidx.room.Query
import androidx.room.Update
import kotlinx.coroutines.flow.Flow

@Dao
interface TaskDao {
    @Query("SELECT * FROM tasks WHERE isArchived = 0 ORDER BY isDone ASC, orderIndex ASC")
    fun observeTasks(): Flow<List<TaskEntity>>

    @Query(
        "SELECT * FROM tasks WHERE isArchived = 1 " +
            "AND (title LIKE :query OR route LIKE :query OR notes LIKE :query) " +
            "ORDER BY createdAt DESC"
    )
    fun observeArchived(query: String): Flow<List<TaskEntity>>

    @Query("SELECT * FROM tasks WHERE id = :id")
    suspend fun getById(id: Long): TaskEntity?

    @Query("SELECT COALESCE(MAX(orderIndex), -1) FROM tasks")
    suspend fun maxOrderIndex(): Int

    @Query("SELECT * FROM tasks")
    suspend fun getAllOnce(): List<TaskEntity>

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

    @Delete
    suspend fun delete(task: TaskEntity)

    @Query("DELETE FROM tasks")
    suspend fun deleteAll()
}
