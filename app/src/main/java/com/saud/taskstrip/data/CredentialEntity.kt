package com.saud.taskstrip.data

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import java.util.UUID

@Entity(
    tableName = "credentials",
    indices = [Index(value = ["syncId"], unique = true)]
)
data class CredentialEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    /** The id both devices agree on — see TaskEntity.syncId. */
    val syncId: String = UUID.randomUUID().toString(),
    /** Last edit, as milliseconds. The merge's first and strongest question: newer wins. */
    val updatedAt: Long = System.currentTimeMillis(),
    /** A tombstone, so a delete can reach the other device instead of looking like a row it
     * simply hasn't heard of yet. */
    val isDeleted: Boolean = false,
    val title: String,
    val username: String = "",
    // AES/GCM ciphertext (Keystore-backed key) — see CredentialCrypto. Never stored in plain text.
    val encryptedPassword: String = "",
    val url: String = "",
    val notes: String = "",
    val createdAt: Long = System.currentTimeMillis()
)
