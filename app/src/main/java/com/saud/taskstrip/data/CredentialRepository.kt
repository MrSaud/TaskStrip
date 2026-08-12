package com.saud.taskstrip.data

import com.saud.taskstrip.security.CredentialCrypto
import kotlinx.coroutines.flow.Flow

class CredentialRepository(private val dao: CredentialDao) {

    val credentials: Flow<List<CredentialEntity>> = dao.observeAll()

    suspend fun add(title: String, username: String, password: String, url: String, notes: String): Long {
        return dao.insert(
            CredentialEntity(
                title = title,
                username = username,
                encryptedPassword = if (password.isBlank()) "" else CredentialCrypto.encrypt(password),
                url = url,
                notes = notes
            )
        )
    }

    // A blank password here means "left untouched in the editor" (the field starts empty on edit
    // so the plaintext is never shown without a biometric reveal) — never treated as "clear it".
    suspend fun update(existing: CredentialEntity, title: String, username: String, password: String, url: String, notes: String) {
        dao.update(
            existing.copy(
                title = title,
                username = username,
                encryptedPassword = if (password.isBlank()) existing.encryptedPassword else CredentialCrypto.encrypt(password),
                url = url,
                notes = notes
            )
        )
    }

    suspend fun delete(credential: CredentialEntity) = dao.delete(credential)

    suspend fun getById(id: Long): CredentialEntity? = dao.getById(id)

    fun decryptPassword(credential: CredentialEntity): String =
        if (credential.encryptedPassword.isBlank()) "" else CredentialCrypto.decrypt(credential.encryptedPassword)
}
