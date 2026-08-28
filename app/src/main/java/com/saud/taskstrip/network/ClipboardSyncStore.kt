package com.saud.taskstrip.network

import android.content.Context
import com.saud.taskstrip.security.BackupPassphraseCrypto

/** Local, Keystore-encrypted storage for the desktop-sync pairing code and whether syncing is
 * turned on — mirrors [com.saud.taskstrip.backup.BackupPassphraseStore]'s exact pattern, reusing
 * the same Keystore-backed encrypt-at-rest helper rather than growing a second one. */
object ClipboardSyncStore {
    private const val PREFS = "clipboard_sync_prefs"
    private const val KEY_ENABLED = "enabled"
    private const val KEY_PAIRING_CODE = "encrypted_pairing_code"

    fun isEnabled(context: Context): Boolean =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean(KEY_ENABLED, false)

    fun setEnabled(context: Context, enabled: Boolean) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putBoolean(KEY_ENABLED, enabled)
            .apply()
    }

    fun getPairingCode(context: Context): String? {
        val stored = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY_PAIRING_CODE, null)
            ?: return null
        return BackupPassphraseCrypto.decrypt(stored)
    }

    fun setPairingCode(context: Context, code: String) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString(KEY_PAIRING_CODE, BackupPassphraseCrypto.encrypt(code))
            .apply()
    }
}
