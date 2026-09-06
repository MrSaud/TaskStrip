package com.saud.taskstrip.data

import androidx.room.Dao
import androidx.room.Delete
import androidx.room.Insert
import androidx.room.Query
import androidx.room.Update
import kotlinx.coroutines.flow.Flow

/** Tombstones are hidden from every query a person sees through — see TaskDao for why they
 * exist at all. [getAllForSync] is the one way to see them, and it is the sync's. */
@Dao
interface StorageItemDao {
    @Query("SELECT * FROM storage_items WHERE isDeleted = 0 ORDER BY createdAt DESC")
    fun observeAll(): Flow<List<StorageItemEntity>>

    @Query("SELECT * FROM storage_items WHERE isDeleted = 0")
    suspend fun getAllOnce(): List<StorageItemEntity>

    /** Tombstones included — see TaskDao.getAllForSync. */
    @Query("SELECT * FROM storage_items")
    suspend fun getAllForSync(): List<StorageItemEntity>

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
