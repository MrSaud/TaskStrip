package com.saud.taskstrip.data

import androidx.room.Dao
import androidx.room.Delete
import androidx.room.Insert
import androidx.room.Query
import androidx.room.Update
import kotlinx.coroutines.flow.Flow

/** The isDeleted filter outlives the board sync that needed it — see TaskDao. */
@Dao
interface CredentialDao {
    @Query("SELECT * FROM credentials WHERE isDeleted = 0 ORDER BY title COLLATE NOCASE ASC")
    fun observeAll(): Flow<List<CredentialEntity>>

    @Query("SELECT * FROM credentials WHERE isDeleted = 0 AND id = :id")
    suspend fun getById(id: Long): CredentialEntity?

    @Query("SELECT * FROM credentials WHERE isDeleted = 0")
    suspend fun getAllOnce(): List<CredentialEntity>

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
