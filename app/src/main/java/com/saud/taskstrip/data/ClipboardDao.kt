package com.saud.taskstrip.data

import androidx.room.Dao
import androidx.room.Delete
import androidx.room.Insert
import androidx.room.Query
import androidx.room.Update
import kotlinx.coroutines.flow.Flow

@Dao
interface ClipboardDao {
    // Pinned first, then newest — the two orders that matter when reaching for a snippet.
    @Query("SELECT * FROM clipboard_items ORDER BY isPinned DESC, createdAt DESC")
    fun observeAll(): Flow<List<ClipboardEntity>>

    @Query("SELECT * FROM clipboard_items")
    suspend fun getAllOnce(): List<ClipboardEntity>

    @Insert
    suspend fun insert(item: ClipboardEntity): Long

    @Insert
    suspend fun insertAll(items: List<ClipboardEntity>)

    @Update
    suspend fun update(item: ClipboardEntity)

    @Delete
    suspend fun delete(item: ClipboardEntity)

    @Query("DELETE FROM clipboard_items WHERE isPinned = 0")
    suspend fun deleteUnpinned()

    @Query("DELETE FROM clipboard_items")
    suspend fun deleteAll()
}
