package com.saud.taskstrip.data

import androidx.room.Dao
import androidx.room.Delete
import androidx.room.Insert
import androidx.room.Query
import androidx.room.Update
import kotlinx.coroutines.flow.Flow

@Dao
interface StorageItemDao {
    @Query("SELECT * FROM storage_items ORDER BY createdAt DESC")
    fun observeAll(): Flow<List<StorageItemEntity>>

    @Query("SELECT * FROM storage_items")
    suspend fun getAllOnce(): List<StorageItemEntity>

    @Insert
    suspend fun insert(item: StorageItemEntity): Long

    @Insert
    suspend fun insertAll(items: List<StorageItemEntity>)

    @Update
    suspend fun update(item: StorageItemEntity)

    @Delete
    suspend fun delete(item: StorageItemEntity)

    @Query("DELETE FROM storage_items")
    suspend fun deleteAll()
}
