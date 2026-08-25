package com.saud.taskstrip.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import androidx.core.content.ContextCompat
import com.saud.taskstrip.MainActivity
import com.saud.taskstrip.R
import com.saud.taskstrip.data.Priority
import com.saud.taskstrip.data.ReminderEntity
import com.saud.taskstrip.data.TaskEntity
import com.saud.taskstrip.ui.components.formatEtaShort

private const val MAX_ROWS = 5
private const val MAX_REMINDER_ROWS = 3

// Reminder ids share the same autoincrement id space style as task ids, so widget PendingIntent
// request codes need this offset to avoid a reminder row's PendingIntent colliding with (and
// silently overwriting) a task row's PendingIntent that happens to share the same numeric id —
// mirrors the REMINDER_SPEECH_ID_BASE / REQUEST_CODE_BASE offset pattern used elsewhere.
private const val REMINDER_REQUEST_CODE_BASE = 200_000

private val ROW_IDS = intArrayOf(
    R.id.widget_row_1, R.id.widget_row_2, R.id.widget_row_3, R.id.widget_row_4, R.id.widget_row_5
)
private val TAG_IDS = intArrayOf(
    R.id.widget_row_1_tag, R.id.widget_row_2_tag, R.id.widget_row_3_tag, R.id.widget_row_4_tag, R.id.widget_row_5_tag
)
private val TITLE_IDS = intArrayOf(
    R.id.widget_row_1_title, R.id.widget_row_2_title, R.id.widget_row_3_title, R.id.widget_row_4_title, R.id.widget_row_5_title
)
private val DUE_IDS = intArrayOf(
    R.id.widget_row_1_due, R.id.widget_row_2_due, R.id.widget_row_3_due, R.id.widget_row_4_due, R.id.widget_row_5_due
)

private val REMINDER_ROW_IDS = intArrayOf(
    R.id.widget_reminder_row_1, R.id.widget_reminder_row_2, R.id.widget_reminder_row_3
)
private val REMINDER_TITLE_IDS = intArrayOf(
    R.id.widget_reminder_row_1_title, R.id.widget_reminder_row_2_title, R.id.widget_reminder_row_3_title
)
private val REMINDER_DUE_IDS = intArrayOf(
    R.id.widget_reminder_row_1_due, R.id.widget_reminder_row_2_due, R.id.widget_reminder_row_3_due
)

private fun Priority.widgetColor(context: Context): Int = ContextCompat.getColor(
    context,
    when (this) {
        Priority.URGENT -> R.color.widget_priority_urgent
        Priority.HIGH -> R.color.widget_priority_high
        Priority.NORMAL -> R.color.widget_priority_normal
        Priority.LOW -> R.color.widget_priority_low
    }
)

object WidgetUpdater {

    // TaskViewModel and ReminderViewModel each only know about their own list, but a single
    // widget render needs both at once — cache whichever came in last from each so an update
    // from either side re-renders the combined view instead of blanking out the other section.
    // Both ViewModels push from viewModelScope (Main dispatcher), so no synchronization needed.
    private var lastTasks: List<TaskEntity> = emptyList()
    private var lastReminders: List<ReminderEntity> = emptyList()

    fun updateTasks(context: Context, activeTasks: List<TaskEntity>) {
        lastTasks = activeTasks
        pushUpdate(context)
    }

    fun updateReminders(context: Context, activeReminders: List<ReminderEntity>) {
        lastReminders = activeReminders
        pushUpdate(context)
    }

    private fun pushUpdate(context: Context) {
        val manager = AppWidgetManager.getInstance(context)
        val ids = manager.getAppWidgetIds(ComponentName(context, TaskStripWidgetProvider::class.java))
        if (ids.isEmpty()) return
        val views = render(context, lastTasks, lastReminders)
        ids.forEach { id -> manager.updateAppWidget(id, views) }
    }

    fun render(context: Context, activeTasks: List<TaskEntity>, activeReminders: List<ReminderEntity>): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.task_strip_widget)

        val openHomeIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val openHomePendingIntent = PendingIntent.getActivity(
            context, 0, openHomeIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        views.setOnClickPendingIntent(R.id.widget_title, openHomePendingIntent)

        val addIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(MainActivity.EXTRA_OPEN_NEW_TASK, true)
        }
        val addPendingIntent = PendingIntent.getActivity(
            context, 1, addIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        views.setOnClickPendingIntent(R.id.widget_add_button, addPendingIntent)

        views.setViewVisibility(R.id.widget_empty_text, if (activeTasks.isEmpty()) android.view.View.VISIBLE else android.view.View.GONE)

        for (i in 0 until MAX_ROWS) {
            val task = activeTasks.getOrNull(i)
            if (task == null) {
                views.setViewVisibility(ROW_IDS[i], android.view.View.GONE)
                continue
            }
            views.setViewVisibility(ROW_IDS[i], android.view.View.VISIBLE)
            views.setInt(TAG_IDS[i], "setBackgroundColor", task.priority.widgetColor(context))
            views.setTextViewText(TITLE_IDS[i], task.title.uppercase())
            views.setTextViewText(DUE_IDS[i], task.dueAt?.let { formatEtaShort(it) } ?: "")

            val openTaskIntent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                putExtra(MainActivity.EXTRA_OPEN_TASK_ID, task.id)
            }
            val openTaskPendingIntent = PendingIntent.getActivity(
                context, 100 + task.id.toInt(), openTaskIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(ROW_IDS[i], openTaskPendingIntent)
        }

        views.setViewVisibility(
            R.id.widget_reminders_empty_text,
            if (activeReminders.isEmpty()) android.view.View.VISIBLE else android.view.View.GONE
        )

        for (i in 0 until MAX_REMINDER_ROWS) {
            val reminder = activeReminders.getOrNull(i)
            if (reminder == null) {
                views.setViewVisibility(REMINDER_ROW_IDS[i], android.view.View.GONE)
                continue
            }
            views.setViewVisibility(REMINDER_ROW_IDS[i], android.view.View.VISIBLE)
            views.setTextViewText(REMINDER_TITLE_IDS[i], reminder.text)
            views.setTextViewText(REMINDER_DUE_IDS[i], formatEtaShort(reminder.triggerAt))

            val openReminderIntent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                putExtra(MainActivity.EXTRA_OPEN_REMINDER_ID, reminder.id)
            }
            val openReminderPendingIntent = PendingIntent.getActivity(
                context,
                REMINDER_REQUEST_CODE_BASE + reminder.id.toInt(),
                openReminderIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(REMINDER_ROW_IDS[i], openReminderPendingIntent)
        }

        return views
    }
}
