package com.saud.taskstrip.widget

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import com.saud.taskstrip.data.AppDatabase
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch

class TaskStripWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        val pendingResult = goAsync()
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val database = AppDatabase.getInstance(context)
                val activeTasks = database.taskDao().observeTasks().first().filter { !it.isDone }
                val activeReminders = database.reminderDao().observeAll().first()
                    .filter { !it.isDone }
                    .sortedBy { it.triggerAt }
                val views = WidgetUpdater.render(context, activeTasks, activeReminders)
                appWidgetIds.forEach { id -> appWidgetManager.updateAppWidget(id, views) }
            } finally {
                pendingResult.finish()
            }
        }
    }
}
