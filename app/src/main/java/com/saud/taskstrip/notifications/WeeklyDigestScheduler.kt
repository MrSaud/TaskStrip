package com.saud.taskstrip.notifications

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.time.ZonedDateTime

object WeeklyDigestScheduler {
    private const val REQUEST_CODE = -2200
    const val WEEKLY_HOUR = 17
    const val WEEKLY_MINUTE = 0
    private val WEEKLY_DAY = DayOfWeek.FRIDAY

    private fun pendingIntent(context: Context): PendingIntent {
        val intent = Intent(context, WeeklyDigestReceiver::class.java)
        return PendingIntent.getBroadcast(
            context,
            REQUEST_CODE,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    /** (Re)arms the next Friday-5pm review — safe to call repeatedly, same reasoning as
     * DigestScheduler.scheduleNext. */
    fun scheduleNext(context: Context) {
        val alarmManager = context.getSystemService(AlarmManager::class.java)
        val zone = ZoneId.systemDefault()
        val now = ZonedDateTime.now(zone)
        var target = LocalDate.now(zone).atTime(LocalTime.of(WEEKLY_HOUR, WEEKLY_MINUTE)).atZone(zone)
        while (target.dayOfWeek != WEEKLY_DAY || !target.isAfter(now)) {
            target = target.plusDays(1)
        }
        alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, target.toInstant().toEpochMilli(), pendingIntent(context))
    }

    fun cancel(context: Context) {
        val alarmManager = context.getSystemService(AlarmManager::class.java)
        alarmManager.cancel(pendingIntent(context))
    }
}
