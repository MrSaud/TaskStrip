package com.saud.taskstrip.notifications

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import com.saud.taskstrip.data.TaskEntity

object FollowUpScheduler {
    const val EXTRA_TASK_ID = "followup_task_id"

    private fun pendingIntent(context: Context, task: TaskEntity): PendingIntent {
        val intent = Intent(context, FollowUpReceiver::class.java).apply {
            putExtra(EXTRA_TASK_ID, task.id)
        }
        return PendingIntent.getBroadcast(
            context,
            task.id.toInt(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    /** Schedules (or clears) the delegation follow-up for a task based on its current
     * waitingOn* fields — same cancel-then-maybe-reschedule shape as ReminderScheduler. */
    fun schedule(context: Context, task: TaskEntity) {
        val alarmManager = context.getSystemService(AlarmManager::class.java)
        val pending = pendingIntent(context, task)
        alarmManager.cancel(pending)

        if (task.isDone || task.isArchived) return
        val since = task.waitingOnSince
        val days = task.waitingOnFollowUpDays
        if (task.waitingOnName.isBlank() || since == null || days == null) return

        val triggerAt = since + days * 24L * 60 * 60 * 1000
        if (triggerAt <= System.currentTimeMillis()) return

        alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pending)
    }

    fun cancel(context: Context, task: TaskEntity) {
        val alarmManager = context.getSystemService(AlarmManager::class.java)
        alarmManager.cancel(pendingIntent(context, task))
    }
}
