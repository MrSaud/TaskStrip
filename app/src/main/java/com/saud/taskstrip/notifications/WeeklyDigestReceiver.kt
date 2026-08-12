package com.saud.taskstrip.notifications

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.saud.taskstrip.data.AppDatabase
import com.saud.taskstrip.ui.components.isDueTodayOrOverdue
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import java.util.concurrent.TimeUnit

class WeeklyDigestReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val appContext = context.applicationContext
        val pendingResult = goAsync()
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val dao = AppDatabase.getInstance(appContext).taskDao()
                val all = dao.getAllOnce()
                val weekAgo = System.currentTimeMillis() - TimeUnit.DAYS.toMillis(7)
                val completedThisWeek = all.filter { it.isDone && (it.completedAt ?: 0L) >= weekAgo }
                val stillOverdue = all.filter { !it.isDone && !it.isArchived && isDueTodayOrOverdue(it.dueAt, it.isDone) }
                NotificationHelper.ensureChannel(appContext)
                NotificationHelper.showWeeklyDigest(appContext, completedThisWeek.size, stillOverdue.size)
            } finally {
                if (WeeklyDigestPrefs.isEnabled(appContext)) {
                    WeeklyDigestScheduler.scheduleNext(appContext)
                }
                pendingResult.finish()
            }
        }
    }
}
