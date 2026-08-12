package com.saud.taskstrip.notifications

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId

object DigestScheduler {
    private const val REQUEST_CODE = -2000
    const val DIGEST_HOUR = 8
    const val DIGEST_MINUTE = 0

    private fun pendingIntent(context: Context): PendingIntent {
        val intent = Intent(context, DigestReceiver::class.java)
        return PendingIntent.getBroadcast(
            context,
            REQUEST_CODE,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    /** (Re)arms the next 8am digest — safe to call repeatedly, e.g. on every app launch, since a
     * fresh PendingIntent with the same request code just replaces whatever was scheduled before. */
    fun scheduleNext(context: Context) {
        val alarmManager = context.getSystemService(AlarmManager::class.java)
        val zone = ZoneId.systemDefault()
        val now = java.time.ZonedDateTime.now(zone)
        var target = LocalDate.now(zone).atTime(LocalTime.of(DIGEST_HOUR, DIGEST_MINUTE)).atZone(zone)
        if (!target.isAfter(now)) {
            target = target.plusDays(1)
        }
        alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, target.toInstant().toEpochMilli(), pendingIntent(context))
    }

    fun cancel(context: Context) {
        val alarmManager = context.getSystemService(AlarmManager::class.java)
        alarmManager.cancel(pendingIntent(context))
    }
}
