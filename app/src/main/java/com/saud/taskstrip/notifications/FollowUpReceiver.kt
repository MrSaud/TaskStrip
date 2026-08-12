package com.saud.taskstrip.notifications

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.saud.taskstrip.data.AppDatabase
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

class FollowUpReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val taskId = intent.getLongExtra(FollowUpScheduler.EXTRA_TASK_ID, -1L)
        if (taskId < 0) return
        val appContext = context.applicationContext
        val pendingResult = goAsync()
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val task = AppDatabase.getInstance(appContext).taskDao().getById(taskId)
                // Re-check freshness at fire time — the strip may have been finished or the
                // delegation cleared since this alarm was scheduled days ago.
                if (task != null && !task.isDone && !task.isArchived && task.waitingOnName.isNotBlank()) {
                    NotificationHelper.ensureChannel(appContext)
                    NotificationHelper.showFollowUp(appContext, task)
                }
            } finally {
                pendingResult.finish()
            }
        }
    }
}
