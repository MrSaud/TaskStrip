package com.saud.taskstrip.backup

import android.content.Context
import com.saud.taskstrip.security.BackupPassphraseCrypto

/** Local, Keystore-encrypted storage for the backup passphrase — lets daily auto-backup encrypt
 * credential passwords without a person present to type it in each time. */
object BackupPassphraseStore {
    private const val PREFS = "backup_passphrase_prefs"
    private const val KEY_VALUE = "encrypted_passphrase"

    fun isSet(context: Context): Boolean =
        !context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY_VALUE, null).isNullOrBlank()

    fun get(context: Context): String? {
        val stored = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY_VALUE, null)
            ?: return null
        return BackupPassphraseCrypto.decrypt(stored)
    }

    fun set(context: Context, passphrase: String) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString(KEY_VALUE, BackupPassphraseCrypto.encrypt(passphrase))
            .apply()
    }

    fun clear(context: Context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().remove(KEY_VALUE).apply()
    }
}
