package com.saud.taskstrip.notifications

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.saud.taskstrip.data.AppDatabase
import com.saud.taskstrip.ui.components.isDueTodayOrOverdue
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

class DigestReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val appContext = context.applicationContext
        val pendingResult = goAsync()
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val dao = AppDatabase.getInstance(appContext).taskDao()
                val due = dao.getAllOnce().filter {
                    !it.isDone && !it.isArchived && isDueTodayOrOverdue(it.dueAt, it.isDone)
                }
                NotificationHelper.ensureChannel(appContext)
                NotificationHelper.showDigest(appContext, due)
            } finally {
                // Re-arm for tomorrow regardless of whether today's digest fired, so a missed or
                // disabled-then-re-enabled digest doesn't need the user to reopen the app first.
                if (DigestPrefs.isEnabled(appContext)) {
                    DigestScheduler.scheduleNext(appContext)
                }
                pendingResult.finish()
            }
        }
    }
}
