package com.saud.taskstrip.notifications

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import com.saud.taskstrip.data.ReminderEntity
import com.saud.taskstrip.ui.components.dueAtAsLocalInstant

object GeneralReminderScheduler {
    const val EXTRA_REMINDER_ID = "reminder_id"
    const val EXTRA_TEXT = "reminder_text"
    const val EXTRA_DESCRIPTION = "reminder_description"

    // Namespaced above any real reminder id (and above FollowUpScheduler's own base) so alarm
    // request codes never collide with a task's due-date reminder, which uses the raw task id.
    const val REQUEST_CODE_BASE = 900_000

    private fun pendingIntent(context: Context, reminder: ReminderEntity): PendingIntent {
        val intent = Intent(context, GeneralReminderReceiver::class.java).apply {
            putExtra(EXTRA_REMINDER_ID, reminder.id)
            putExtra(EXTRA_TEXT, reminder.text)
            putExtra(EXTRA_DESCRIPTION, reminder.description)
        }
        return PendingIntent.getBroadcast(
            context,
            (REQUEST_CODE_BASE + reminder.id).toInt(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    fun schedule(context: Context, reminder: ReminderEntity) {
        val alarmManager = context.getSystemService(AlarmManager::class.java)
        val pending = pendingIntent(context, reminder)
        alarmManager.cancel(pending)

        if (reminder.isDone) return

        // triggerAt is stored/displayed as a UTC-treated wall-clock value (see the comment on
        // dueAtAsLocalInstant) so it round-trips through the picker correctly — but AlarmManager
        // needs a real instant, so re-anchor to the device's actual timezone before scheduling.
        // leadMinutesBefore (if set) shifts the actual alarm earlier than the reminder's own
        // moment — there's only ever one alarm, not a separate one at triggerAt too.
        val leadMillis = (reminder.leadMinutesBefore ?: 0) * 60_000L
        val realTriggerAt = dueAtAsLocalInstant(reminder.triggerAt) - leadMillis
        if (realTriggerAt <= System.currentTimeMillis()) return

        alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, realTriggerAt, pending)
    }

    fun cancel(context: Context, reminder: ReminderEntity) {
        val alarmManager = context.getSystemService(AlarmManager::class.java)
        alarmManager.cancel(pendingIntent(context, reminder))
    }
}
