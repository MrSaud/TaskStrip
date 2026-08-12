package com.saud.taskstrip.notifications

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationManagerCompat
import com.saud.taskstrip.data.AppDatabase
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

class ReminderReceiver : BroadcastReceiver() {

    companion object {
        const val ACTION_MARK_DONE = "com.saud.taskstrip.ACTION_MARK_DONE"
    }

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            ACTION_MARK_DONE -> handleMarkDone(context, intent)
            else -> handleFire(context, intent)
        }
    }

    private fun handleFire(context: Context, intent: Intent) {
        val taskId = intent.getLongExtra(ReminderScheduler.EXTRA_TASK_ID, -1L)
        if (taskId < 0) return
        val title = intent.getStringExtra(ReminderScheduler.EXTRA_TITLE).orEmpty()
        val tags = intent.getStringExtra(ReminderScheduler.EXTRA_TAGS).orEmpty()
        NotificationHelper.ensureChannel(context)
        NotificationHelper.show(context, taskId, title, tags)
    }

    // Lets "MARK DONE" be tapped straight from the notification (including on a bridged
    // smartwatch) without opening the app.
    private fun handleMarkDone(context: Context, intent: Intent) {
        val taskId = intent.getLongExtra(ReminderScheduler.EXTRA_TASK_ID, -1L)
        if (taskId < 0) return
        val appContext = context.applicationContext
        val pendingResult = goAsync()
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val dao = AppDatabase.getInstance(appContext).taskDao()
                dao.getById(taskId)?.let { task -> dao.update(task.copy(isDone = true)) }
            } finally {
                NotificationManagerCompat.from(appContext).cancel(taskId.toInt())
                pendingResult.finish()
            }
        }
    }
}
