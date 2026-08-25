package com.saud.taskstrip

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.saud.taskstrip.data.ReminderEntity
import com.saud.taskstrip.data.ReminderRepository
import com.saud.taskstrip.notifications.GeneralReminderScheduler
import com.saud.taskstrip.widget.WidgetUpdater
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

class ReminderViewModel(
    application: Application,
    private val repository: ReminderRepository
) : AndroidViewModel(application) {

    val reminders: StateFlow<List<ReminderEntity>> = repository.reminders
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    init {
        viewModelScope.launch {
            reminders.collect { list ->
                val active = list.filter { !it.isDone }.sortedBy { it.triggerAt }
                WidgetUpdater.updateReminders(getApplication(), active)
            }
        }
    }

    // Set by voice quick-add so the editor can pre-fill the dictated text; consumed once so a
    // process recreation or back-navigation doesn't replay it into a later, unrelated entry.
    private var pendingText: String? = null
    fun setPendingText(text: String) { pendingText = text }
    fun consumePendingText(): String? = pendingText.also { pendingText = null }

    fun add(
        text: String,
        description: String,
        triggerAt: Long,
        leadMinutesBefore: Int?,
        repeatAmount: Int?,
        repeatUnit: String?,
        tag: String,
        tagEmoji: String
    ) {
        viewModelScope.launch {
            val reminder = repository.add(text, description, triggerAt, leadMinutesBefore, repeatAmount, repeatUnit, tag, tagEmoji)
            GeneralReminderScheduler.schedule(getApplication(), reminder)
        }
    }

    fun update(
        existing: ReminderEntity,
        text: String,
        description: String,
        triggerAt: Long,
        leadMinutesBefore: Int?,
        repeatAmount: Int?,
        repeatUnit: String?,
        tag: String,
        tagEmoji: String,
        isDone: Boolean
    ) {
        viewModelScope.launch {
            val updated = repository.update(existing, text, description, triggerAt, leadMinutesBefore, repeatAmount, repeatUnit, tag, tagEmoji, isDone)
            GeneralReminderScheduler.schedule(getApplication(), updated)
        }
    }

    fun toggleDone(reminder: ReminderEntity) {
        viewModelScope.launch {
            val updated = repository.update(
                reminder,
                reminder.text,
                reminder.description,
                reminder.triggerAt,
                reminder.leadMinutesBefore,
                reminder.repeatAmount,
                reminder.repeatUnit,
                reminder.tag,
                reminder.tagEmoji,
                !reminder.isDone
            )
            GeneralReminderScheduler.schedule(getApplication(), updated)
        }
    }

    fun delete(reminder: ReminderEntity) {
        viewModelScope.launch {
            GeneralReminderScheduler.cancel(getApplication(), reminder)
            repository.delete(reminder)
        }
    }

    suspend fun getById(id: Long): ReminderEntity? = repository.getById(id)
}

class ReminderViewModelFactory(
    private val application: Application,
    private val repository: ReminderRepository
) : ViewModelProvider.Factory {
    override fun <T : androidx.lifecycle.ViewModel> create(modelClass: Class<T>): T {
        @Suppress("UNCHECKED_CAST")
        return ReminderViewModel(application, repository) as T
    }
}
