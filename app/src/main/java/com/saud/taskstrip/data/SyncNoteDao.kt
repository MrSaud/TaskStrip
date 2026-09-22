package com.saud.taskstrip.data

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import kotlinx.coroutines.flow.Flow

@Dao
interface SyncNoteDao {
    /** Tombstones are filtered out here rather than at the screen, so nothing can accidentally
     * show one. The sync needs them and asks for everything instead. */
    @Query("SELECT * FROM sync_notes WHERE isDeleted = 0 ORDER BY updatedAt DESC")
    fun observeVisible(): Flow<List<SyncNoteEntity>>

    @Query("SELECT * FROM sync_notes")
    suspend fun getAllOnce(): List<SyncNoteEntity>

    @Query("SELECT * FROM sync_notes WHERE id = :id")
    suspend fun byId(id: String): SyncNoteEntity?

    /** Replace, because the merge writes back rows that already exist by the same shared id. */
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(note: SyncNoteEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertAll(notes: List<SyncNoteEntity>)

    @Update
    suspend fun update(note: SyncNoteEntity)

    @Query("DELETE FROM sync_notes")
    suspend fun deleteAll()
}
