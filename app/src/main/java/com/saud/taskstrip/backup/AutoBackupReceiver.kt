package com.saud.taskstrip.backup

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.saud.taskstrip.data.AppDatabase
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

class AutoBackupReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val appContext = context.applicationContext
        val pendingResult = goAsync()
        CoroutineScope(Dispatchers.IO).launch {
            try {
                // No signed-in account (or the user revoked Drive access) — nothing to do until
                // they sign back in from the Backup screen; fail silently rather than nagging via
                // notification every night.
                val account = DriveAuthHelper.signedInAccount(appContext) ?: return@launch
                val token = DriveAuthHelper.getAccessToken(appContext, account) ?: return@launch
                val folderId = DriveApi.ensureBackupFolder(token) ?: return@launch

                val database = AppDatabase.getInstance(appContext)
                val passphrase = BackupPassphraseStore.get(appContext)
                val zip = BackupHelper.createBackupZip(
                    appContext,
                    database.taskDao(),
                    database.credentialDao(),
                    database.noteDao(),
                    database.reminderDao(),
                    database.storageItemDao(),
                    passphrase
                )
                DriveApi.uploadBackup(token, folderId, zip, BackupHelper.backupFileName())
                zip.delete()
            } finally {
                if (AutoBackupPrefs.isEnabled(appContext)) {
                    AutoBackupScheduler.scheduleNext(appContext)
                }
                pendingResult.finish()
            }
        }
    }
}
