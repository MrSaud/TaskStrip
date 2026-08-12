package com.saud.taskstrip.data

import androidx.room.Dao
import androidx.room.Delete
import androidx.room.Insert
import androidx.room.Query
import androidx.room.Update
import kotlinx.coroutines.flow.Flow

@Dao
interface CredentialDao {
    @Query("SELECT * FROM credentials ORDER BY title COLLATE NOCASE ASC")
    fun observeAll(): Flow<List<CredentialEntity>>

    @Query("SELECT * FROM credentials WHERE id = :id")
    suspend fun getById(id: Long): CredentialEntity?

    @Query("SELECT * FROM credentials")
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
