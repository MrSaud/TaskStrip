package com.saud.taskstrip.sync

import android.content.Context

/** What the board sync has to remember between runs. */
object BoardSyncPrefs {
    private const val PREFS = "board_sync_prefs"
    private const val KEY_HAS_SYNCED = "has_synced"
    private const val KEY_LAST_SUMMARY = "last_summary"
    private const val KEY_LAST_AT = "last_at"

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    /**
     * Whether this device has ever completed a sync.
     *
     * Only used to decide the first-sync stance — see SyncBoardPlan.stance. On this device it can
     * only ever lead to a merge, because the phone is the side that wins: it is the Mac that gives
     * way once, so that two boards which already overlap don't become one board of duplicates.
     */
    fun hasSyncedBefore(context: Context): Boolean =
        prefs(context).getBoolean(KEY_HAS_SYNCED, false)

    fun markSynced(context: Context, summary: String, at: Long = System.currentTimeMillis()) {
        prefs(context).edit()
            .putBoolean(KEY_HAS_SYNCED, true)
            .putString(KEY_LAST_SUMMARY, summary)
            .putLong(KEY_LAST_AT, at)
            .apply()
    }

    fun lastSummary(context: Context): String? =
        prefs(context).getString(KEY_LAST_SUMMARY, null)

    fun lastSyncedAt(context: Context): Long = prefs(context).getLong(KEY_LAST_AT, 0L)
}
