package com.saud.taskstrip.notifications

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.saud.taskstrip.MainActivity
import com.saud.taskstrip.data.TaskEntity

object NotificationHelper {
    const val CHANNEL_ID = "task_reminders"
    const val BADGE_CHANNEL_ID = "active_tasks_badge"
    const val DIGEST_CHANNEL_ID = "daily_digest"
    const val WEEKLY_DIGEST_CHANNEL_ID = "weekly_digest"
    const val FOLLOWUP_CHANNEL_ID = "follow_up"
    const val GENERAL_REMINDER_CHANNEL_ID = "general_reminders"
    private const val BADGE_NOTIFICATION_ID = -1000
    private const val DIGEST_NOTIFICATION_ID = -3000
    private const val WEEKLY_DIGEST_NOTIFICATION_ID = -4000
    // Follow-up notification ids are namespaced above any real task id so they never collide
    // with that same task's due-date reminder notification (which uses the raw task id).
    private const val FOLLOWUP_ID_BASE = 500_000

    fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Task reminders",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Reminders before a task's due date"
            }
            val badgeChannel = NotificationChannel(
                BADGE_CHANNEL_ID,
                "Active tasks badge",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Silent, ongoing counter that powers the Task Strips app icon badge"
                setShowBadge(true)
            }
            val digestChannel = NotificationChannel(
                DIGEST_CHANNEL_ID,
                "Daily digest",
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                description = "One morning summary of strips due today or overdue"
            }
            val weeklyDigestChannel = NotificationChannel(
                WEEKLY_DIGEST_CHANNEL_ID,
                "Weekly review",
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                description = "Friday summary of what got done this week and what's still overdue"
            }
            val followUpChannel = NotificationChannel(
                FOLLOWUP_CHANNEL_ID,
                "Follow-ups",
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                description = "Reminder to follow up on a strip you delegated"
            }
            val generalReminderChannel = NotificationChannel(
                GENERAL_REMINDER_CHANNEL_ID,
                "Reminders",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Reminders you set directly, not tied to a strip"
            }
            val manager = context.getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
            manager.createNotificationChannel(badgeChannel)
            manager.createNotificationChannel(digestChannel)
            manager.createNotificationChannel(weeklyDigestChannel)
            manager.createNotificationChannel(followUpChannel)
            manager.createNotificationChannel(generalReminderChannel)
        }
    }

    /** Shows the once-a-day summary of due-today/overdue strips — silently does nothing when
     * there's nothing due, so the digest stays quiet on days with a clear board. */
    fun showDigest(context: Context, dueTasks: List<TaskEntity>) {
        if (dueTasks.isEmpty()) return

        val hasPermission = Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED
        if (!hasPermission) return

        val openIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            context,
            DIGEST_NOTIFICATION_ID,
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val title = if (dueTasks.size == 1) "1 strip needs attention today" else "${dueTasks.size} strips need attention today"
        val lines = dueTasks.take(5).map { it.title.uppercase() }
        val style = NotificationCompat.InboxStyle().also { inbox ->
            lines.forEach { inbox.addLine(it) }
            if (dueTasks.size > lines.size) inbox.addLine("+ ${dueTasks.size - lines.size} more")
            inbox.setBigContentTitle(title)
        }

        val notification = NotificationCompat.Builder(context, DIGEST_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(title)
            .setContentText(lines.joinToString(", "))
            .setStyle(style)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .build()
        NotificationManagerCompat.from(context).notify(DIGEST_NOTIFICATION_ID, notification)
    }

    /** Shows the Friday week-in-review — silently does nothing when there's genuinely nothing to
     * report (no completions and no overdue strips). */
    fun showWeeklyDigest(context: Context, completedCount: Int, overdueCount: Int) {
        if (completedCount == 0 && overdueCount == 0) return

        val hasPermission = Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED
        if (!hasPermission) return

        val openIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            context,
            WEEKLY_DIGEST_NOTIFICATION_ID,
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val doneText = if (completedCount == 1) "1 strip done" else "$completedCount strips done"
        val overdueText = if (overdueCount == 1) "1 still overdue" else "$overdueCount still overdue"
        val notification = NotificationCompat.Builder(context, WEEKLY_DIGEST_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle("Week in review")
            .setContentText("$doneText · $overdueText")
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .build()
        NotificationManagerCompat.from(context).notify(WEEKLY_DIGEST_NOTIFICATION_ID, notification)
    }

    /** Fires when a delegated strip is still open after its follow-up window — a no-op silently
     * skips if permission isn't granted, same as every other notification here. */
    fun showFollowUp(context: Context, task: TaskEntity) {
        val hasPermission = Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED
        if (!hasPermission) return

        val openIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(MainActivity.EXTRA_OPEN_TASK_ID, task.id)
        }
        val notificationId = (FOLLOWUP_ID_BASE + task.id).toInt()
        val pendingIntent = PendingIntent.getActivity(
            context,
            notificationId,
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(context, FOLLOWUP_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle("Follow up with ${task.waitingOnName}")
            .setContentText(task.title.uppercase())
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .build()
        NotificationManagerCompat.from(context).notify(notificationId, notification)
    }

    /** Keeps the launcher icon badge in sync with the active-task count via a silent, ongoing notification. */
    fun updateBadge(context: Context, activeCount: Int) {
        val hasPermission = Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED
        if (!hasPermission) return

        if (activeCount <= 0) {
            NotificationManagerCompat.from(context).cancel(BADGE_NOTIFICATION_ID)
            return
        }

        val openIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            context,
            BADGE_NOTIFICATION_ID,
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val label = if (activeCount == 1) "1 active strip" else "$activeCount active strips"
        val notification = NotificationCompat.Builder(context, BADGE_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(label)
            .setContentText("Tap to open Task Strips")
            .setNumber(activeCount)
            .setOngoing(true)
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_STATUS)
            .setContentIntent(pendingIntent)
            .build()
        NotificationManagerCompat.from(context).notify(BADGE_NOTIFICATION_ID, notification)
    }

    /** Shows a standalone reminder — one the user set directly, not tied to any strip. */
    fun showReminder(context: Context, reminderId: Long, title: String, description: String) {
        val hasPermission = Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED
        if (!hasPermission) return

        val openIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val notificationId = (GeneralReminderScheduler.REQUEST_CODE_BASE + reminderId).toInt()
        val pendingIntent = PendingIntent.getActivity(
            context,
            notificationId,
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(context, GENERAL_REMINDER_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(title)
            .setContentText(description.ifBlank { "Reminder" })
            .apply { if (description.isNotBlank()) setStyle(NotificationCompat.BigTextStyle().bigText(description)) }
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .build()
        NotificationManagerCompat.from(context).notify(notificationId, notification)
    }

    fun show(context: Context, taskId: Long, title: String, tags: String) {
        val openIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(MainActivity.EXTRA_OPEN_TASK_ID, taskId)
        }
        val pendingIntent = PendingIntent.getActivity(
            context,
            taskId.toInt(),
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val markDoneIntent = Intent(context, ReminderReceiver::class.java).apply {
            action = ReminderReceiver.ACTION_MARK_DONE
            putExtra(ReminderScheduler.EXTRA_TASK_ID, taskId)
        }
        val markDonePendingIntent = PendingIntent.getBroadcast(
            context,
            taskId.toInt(),
            markDoneIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // A proper NotificationChannel notification like this is automatically bridged to a
        // paired Wear OS / Galaxy Watch by the system — no extra code needed for it to show up
        // there. The action below also appears as a tappable button on the watch.
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(title.uppercase())
            .setContentText(if (tags.isNotBlank()) "Due soon · ${tags.uppercase()}" else "Due soon")
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .addAction(android.R.drawable.checkbox_on_background, "MARK DONE", markDonePendingIntent)
            .build()

        val hasPermission = Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED
        if (hasPermission) {
            NotificationManagerCompat.from(context).notify(taskId.toInt(), notification)
        }
    }
}
