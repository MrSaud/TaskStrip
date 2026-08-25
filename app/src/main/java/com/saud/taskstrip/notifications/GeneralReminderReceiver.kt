package com.saud.taskstrip.notifications

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.saud.taskstrip.data.AppDatabase
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.ZoneOffset

class GeneralReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val reminderId = intent.getLongExtra(GeneralReminderScheduler.EXTRA_REMINDER_ID, -1L)
        if (reminderId < 0) return
        val text = intent.getStringExtra(GeneralReminderScheduler.EXTRA_TEXT).orEmpty()
        val description = intent.getStringExtra(GeneralReminderScheduler.EXTRA_DESCRIPTION).orEmpty()
        NotificationHelper.ensureChannel(context)
        NotificationHelper.showReminder(context, reminderId, text, description)

        // Advance a repeating reminder to its next occurrence and reschedule — this has to happen
        // once per actual firing (here), not once per schedule() call, or it would advance every
        // time the reminder is merely edited/saved.
        val appContext = context.applicationContext
        val pendingResult = goAsync()
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val dao = AppDatabase.getInstance(appContext).reminderDao()
                val reminder = dao.getById(reminderId) ?: return@launch
                val amount = reminder.repeatAmount
                val unit = reminder.repeatUnit
                if (amount != null && amount > 0 && unit != null) {
                    val updated = reminder.copy(triggerAt = nextOccurrence(reminder.triggerAt, amount, unit))
                    dao.update(updated)
                    GeneralReminderScheduler.schedule(appContext, updated)
                }
            } finally {
                pendingResult.finish()
            }
        }
    }

    // triggerAt is stored/displayed as a UTC-treated wall-clock value (the same convention used
    // for every other date field in this app) so it round-trips through the picker correctly —
    // advance those same wall-clock digits with calendar arithmetic (not a fixed day count) so a
    // monthly/yearly repeat lands on the same day-of-month/date instead of drifting.
    private fun nextOccurrence(triggerAt: Long, amount: Int, unit: String): Long {
        val zdt = Instant.ofEpochMilli(triggerAt).atZone(ZoneOffset.UTC)
        val next = when (unit) {
            "DAILY" -> zdt.plusDays(amount.toLong())
            "WEEKLY" -> zdt.plusWeeks(amount.toLong())
            "MONTHLY" -> zdt.plusMonths(amount.toLong())
            "YEARLY" -> zdt.plusYears(amount.toLong())
            else -> zdt
        }
        return next.toInstant().toEpochMilli()
    }
}
