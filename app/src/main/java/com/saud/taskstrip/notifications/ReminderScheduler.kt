package com.saud.taskstrip.notifications

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import com.saud.taskstrip.data.TaskEntity
import com.saud.taskstrip.ui.components.dueAtAsLocalInstant

object ReminderScheduler {
    const val EXTRA_TASK_ID = "task_id"
    const val EXTRA_TITLE = "task_title"
    const val EXTRA_TAGS = "task_tags"

    private fun pendingIntent(context: Context, task: TaskEntity): PendingIntent {
        val intent = Intent(context, ReminderReceiver::class.java).apply {
            putExtra(EXTRA_TASK_ID, task.id)
            putExtra(EXTRA_TITLE, task.title)
            putExtra(EXTRA_TAGS, task.tags.joinToString(", "))
        }
        return PendingIntent.getBroadcast(
            context,
            task.id.toInt(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    /** Schedules (or clears) the due-date reminder for a task based on its current fields. */
    fun schedule(context: Context, task: TaskEntity) {
        val alarmManager = context.getSystemService(AlarmManager::class.java)
        val pending = pendingIntent(context, task)
        alarmManager.cancel(pending)

        val dueAt = task.dueAt
        val leadMinutes = task.reminderMinutesBefore
        if (task.isDone || task.isArchived || dueAt == null || leadMinutes == null) return

        // dueAt is stored/displayed as a UTC-treated wall-clock value (see the comment on
        // dueAtAsLocalInstant) so it round-trips through the picker correctly — but AlarmManager
        // needs a real instant, so re-anchor to the device's actual timezone before scheduling.
        val triggerAt = dueAtAsLocalInstant(dueAt) - leadMinutes * 60_000L
        if (triggerAt <= System.currentTimeMillis()) return

        alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pending)
    }

    fun cancel(context: Context, task: TaskEntity) {
        val alarmManager = context.getSystemService(AlarmManager::class.java)
        alarmManager.cancel(pendingIntent(context, task))
    }
}
