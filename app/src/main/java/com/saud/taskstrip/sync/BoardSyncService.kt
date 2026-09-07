package com.saud.taskstrip.sync

import android.content.Context
import com.saud.taskstrip.backup.BackupPassphraseStore
import com.saud.taskstrip.backup.DriveAuthHelper
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * One sync, from the outside: get a token, run it, remember what happened.
 *
 * The phone never adopts. Whichever device gives way on a first sync is the user's choice, and it
 * is the Mac — so this always merges, and the only thing hasSyncedBefore does here is stay true.
 */
object BoardSyncService {

    suspend fun run(context: Context): BoardSyncOutcome = withContext(Dispatchers.IO) {
        val account = DriveAuthHelper.signedInAccount(context)
            ?: return@withContext BoardSyncOutcome(failure = "Sign in to Google Drive first.")
        val token = DriveAuthHelper.getAccessToken(context, account)
            ?: return@withContext BoardSyncOutcome(failure = "Couldn't get a Drive token.")

        val outcome = runCatching {
            BoardSyncRunner(
                context = context,
                transport = DriveBoardTransport(token),
                // The same passphrase the backup uses. Without one a credential's password stays
                // on this device rather than travelling in the clear — see BoardSyncRunner.
                passphrase = BackupPassphraseStore.get(context)
            ).run(
                hasSyncedBefore = BoardSyncPrefs.hasSyncedBefore(context),
                adoptsOnFirstSync = false
            )
        }.getOrElse { error ->
            BoardSyncOutcome(failure = error.message ?: "Sync failed.")
        }

        // Recorded only when the sync got somewhere *and* there was a board on the other side.
        // The phone never adopts, so this changes nothing here — but the two services answer the
        // same question and should answer it the same way. See BoardSyncService.swift, where
        // getting this wrong cost the Mac its one chance to adopt.
        if (outcome.failure == null && outcome.metRemoteBoard) {
            BoardSyncPrefs.markSynced(context, outcome.summary)
        }
        outcome
    }
}
