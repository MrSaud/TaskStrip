package com.saud.taskstrip.data

import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "credentials")
data class CredentialEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val title: String,
    val username: String = "",
    // AES/GCM ciphertext (Keystore-backed key) — see CredentialCrypto. Never stored in plain text.
    val encryptedPassword: String = "",
    val url: String = "",
    val notes: String = "",
    val createdAt: Long = System.currentTimeMillis()
)
