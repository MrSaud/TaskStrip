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
interface CredentialDao {
    @Query("SELECT * FROM credentials WHERE isDeleted = 0 ORDER BY title COLLATE NOCASE ASC")
    fun observeAll(): Flow<List<CredentialEntity>>

    @Query("SELECT * FROM credentials WHERE isDeleted = 0 AND id = :id")
    suspend fun getById(id: Long): CredentialEntity?

    @Query("SELECT * FROM credentials WHERE isDeleted = 0")
    suspend fun getAllOnce(): List<CredentialEntity>

    /** Tombstones included — see TaskDao.getAllForSync. */
    @Query("SELECT * FROM credentials")
    suspend fun getAllForSync(): List<CredentialEntity>

    @Insert
    suspend fun insert(credential: CredentialEntity): Long

    @Insert
    suspend fun insertAll(credentials: List<CredentialEntity>)

    @Update
    suspend fun update(credential: CredentialEntity)

    @Delete
    suspend fun delete(credential: CredentialEntity)

    @Query("DELETE FROM credentials")
    suspend fun deleteAll()
}
