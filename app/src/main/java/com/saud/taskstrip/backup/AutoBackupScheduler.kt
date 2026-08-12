package com.saud.taskstrip.backup

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.time.ZonedDateTime

object AutoBackupScheduler {
    private const val REQUEST_CODE = -2300
    const val BACKUP_HOUR = 3
    const val BACKUP_MINUTE = 0

    private fun pendingIntent(context: Context): PendingIntent {
        val intent = Intent(context, AutoBackupReceiver::class.java)
        return PendingIntent.getBroadcast(
            context,
            REQUEST_CODE,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    /** (Re)arms the next 3am backup — safe to call repeatedly, same reasoning as
     * DigestScheduler.scheduleNext. A quiet, off-peak hour so it doesn't compete with anything
     * the user is actively doing on the device. */
    fun scheduleNext(context: Context) {
        val alarmManager = context.getSystemService(AlarmManager::class.java)
        val zone = ZoneId.systemDefault()
        val now = ZonedDateTime.now(zone)
        var target = LocalDate.now(zone).atTime(LocalTime.of(BACKUP_HOUR, BACKUP_MINUTE)).atZone(zone)
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
