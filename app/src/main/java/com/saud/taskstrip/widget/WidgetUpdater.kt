package com.saud.taskstrip.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import androidx.core.content.ContextCompat
import com.saud.taskstrip.MainActivity
import com.saud.taskstrip.R
import com.saud.taskstrip.data.Priority
import com.saud.taskstrip.data.TaskEntity
import com.saud.taskstrip.ui.components.formatEtaShort

private const val MAX_ROWS = 5

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

    /** Renders the given active tasks (already board-ordered) into every placed widget instance. */
    fun updateAll(context: Context, activeTasks: List<TaskEntity>) {
        val manager = AppWidgetManager.getInstance(context)
        val ids = manager.getAppWidgetIds(android.content.ComponentName(context, TaskStripWidgetProvider::class.java))
        if (ids.isEmpty()) return
        val views = render(context, activeTasks)
        ids.forEach { id -> manager.updateAppWidget(id, views) }
    }

    fun render(context: Context, activeTasks: List<TaskEntity>): RemoteViews {
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

        return views
    }
}
