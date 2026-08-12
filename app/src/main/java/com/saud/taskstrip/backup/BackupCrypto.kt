package com.saud.taskstrip.backup

import android.util.Base64
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.PBEKeySpec
import javax.crypto.spec.SecretKeySpec

/**
 * Passphrase-derived AES/GCM encryption for credential passwords going into a backup file.
 *
 * This is deliberately NOT the same as [com.saud.taskstrip.security.CredentialCrypto]: that key
 * lives only in this device's Android Keystore and can't be exported, so a value encrypted with it
 * is permanently unreadable on any other device (and often even on the same device after a
 * reinstall). A backup has to survive exactly those situations, so credential passwords are
 * re-encrypted here with a key derived from a passphrase the user chooses and remembers — the only
 * secret that travels with the backup is the passphrase itself, never the key.
 */
object BackupCrypto {
    private const val ITERATIONS = 120_000
    private const val KEY_LENGTH_BITS = 256
    private const val GCM_TAG_LENGTH_BITS = 128
    private const val TRANSFORMATION = "AES/GCM/NoPadding"

    data class Encrypted(val salt: String, val iv: String, val cipher: String)

    private fun deriveKey(passphrase: String, salt: ByteArray): SecretKeySpec {
        val factory = SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256")
        val spec = PBEKeySpec(passphrase.toCharArray(), salt, ITERATIONS, KEY_LENGTH_BITS)
        return SecretKeySpec(factory.generateSecret(spec).encoded, "AES")
    }

    fun encrypt(plainText: String, passphrase: String): Encrypted {
        val salt = ByteArray(16).also { SecureRandom().nextBytes(it) }
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, deriveKey(passphrase, salt))
        val cipherBytes = cipher.doFinal(plainText.toByteArray(Charsets.UTF_8))
        return Encrypted(
            salt = Base64.encodeToString(salt, Base64.NO_WRAP),
            iv = Base64.encodeToString(cipher.iv, Base64.NO_WRAP),
            cipher = Base64.encodeToString(cipherBytes, Base64.NO_WRAP)
        )
    }

    /** Returns null on any failure (wrong passphrase, corrupted/tampered data) instead of
     * throwing — GCM's auth tag makes a wrong key reliably detectable rather than silently
     * producing garbage, so callers can treat null as "couldn't decrypt this one" and move on. */
    fun decrypt(encrypted: Encrypted, passphrase: String): String? = try {
        val salt = Base64.decode(encrypted.salt, Base64.NO_WRAP)
        val iv = Base64.decode(encrypted.iv, Base64.NO_WRAP)
        val cipherBytes = Base64.decode(encrypted.cipher, Base64.NO_WRAP)
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.DECRYPT_MODE, deriveKey(passphrase, salt), GCMParameterSpec(GCM_TAG_LENGTH_BITS, iv))
        String(cipher.doFinal(cipherBytes), Charsets.UTF_8)
    } catch (e: Exception) {
        null
    }
}
