package com.saud.taskstrip.backup

import android.content.Context

object AutoBackupPrefs {
    private const val PREFS = "auto_backup_prefs"
    private const val KEY_ENABLED = "enabled"

    // Off by default: unlike the digest notifications, this silently uploads user data over the
    // network the moment it's turned on — that should be an opt-in the user reaches for after
    // signing in to Drive, not something switched on before they've connected an account at all.
    fun isEnabled(context: Context): Boolean =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean(KEY_ENABLED, false)

    fun setEnabled(context: Context, enabled: Boolean) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putBoolean(KEY_ENABLED, enabled).apply()
    }
}
