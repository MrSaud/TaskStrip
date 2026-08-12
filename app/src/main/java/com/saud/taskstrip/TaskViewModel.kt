package com.saud.taskstrip

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.saud.taskstrip.data.Priority
import com.saud.taskstrip.data.TaskActionLogEntry
import com.saud.taskstrip.data.TaskContact
import com.saud.taskstrip.data.TaskEntity
import com.saud.taskstrip.data.TaskRepository
import com.saud.taskstrip.notifications.FollowUpScheduler
import com.saud.taskstrip.notifications.NotificationHelper
import com.saud.taskstrip.notifications.ReminderScheduler
import com.saud.taskstrip.quotes.Quote
import com.saud.taskstrip.quotes.QuoteCache
import com.saud.taskstrip.quotes.QuoteOfTheDayApi
import com.saud.taskstrip.voice.VoiceDraft
import com.saud.taskstrip.widget.WidgetUpdater
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

class TaskViewModel(
    application: Application,
    private val repository: TaskRepository
) : AndroidViewModel(application) {

    val tasks: StateFlow<List<TaskEntity>> = repository.tasks
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    private val _quote = MutableStateFlow<Quote?>(null)
    val quote: StateFlow<Quote?> = _quote

    init {
        viewModelScope.launch {
            tasks.collect { list ->
                val active = list.filter { !it.isDone }
                NotificationHelper.updateBadge(getApplication(), active.size)
                WidgetUpdater.updateAll(getApplication(), active)
            }
        }
        viewModelScope.launch {
            val cached = QuoteCache.get(getApplication())
            if (cached != null) {
                _quote.value = cached
            } else {
                QuoteOfTheDayApi.fetch()?.let { fetched ->
                    _quote.value = fetched
                    QuoteCache.save(getApplication(), fetched)
                }
            }
        }
    }

    private val archiveQuery = MutableStateFlow("")

    @OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)
    val archivedTasks: StateFlow<List<TaskEntity>> = archiveQuery
        .flatMapLatest { query -> repository.observeArchivedTasks(query) }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    fun setArchiveQuery(query: String) {
        archiveQuery.value = query
    }

    // One-shot holder for a draft strip from voice quick-add or a shared link/text: whichever
    // source sets it, the editor reads and clears it once when opening a new (unsaved) strip.
    private var pendingDraft: VoiceDraft? = null

    fun setPendingDraft(draft: VoiceDraft) {
        pendingDraft = draft
    }

    fun consumePendingDraft(): VoiceDraft? {
        val draft = pendingDraft
        pendingDraft = null
        return draft
    }

    fun addTask(
        title: String,
        route: String,
        notes: String,
        priority: Priority,
        dueAt: Long?,
        progress: Int,
        images: List<String>,
        voiceNotes: List<String>,
        documents: List<String>,
        videos: List<String>,
        reminderMinutesBefore: Int?,
        repeatIntervalDays: Int? = null,
        contacts: List<TaskContact> = emptyList(),
        tags: List<String> = emptyList(),
        linkedSketchId: String? = null,
        actionLog: List<TaskActionLogEntry> = emptyList()
    ) {
        viewModelScope.launch {
            val id = repository.addTask(
                title, route, notes, priority, dueAt, progress, images, voiceNotes, documents, videos,
                reminderMinutesBefore, repeatIntervalDays, contacts, tags, linkedSketchId, actionLog
            )
            repository.getTask(id)?.let { ReminderScheduler.schedule(getApplication(), it) }
        }
    }

    fun addContactToTask(task: TaskEntity, contact: TaskContact) {
        viewModelScope.launch {
            repository.addContactToTask(task, contact)
        }
    }

    fun updateTask(task: TaskEntity) {
        viewModelScope.launch {
            repository.updateTask(task)
            ReminderScheduler.schedule(getApplication(), task)
            FollowUpScheduler.schedule(getApplication(), task)
        }
    }

    fun deleteTask(task: TaskEntity) {
        viewModelScope.launch {
            repository.deleteTask(task)
            ReminderScheduler.cancel(getApplication(), task)
            FollowUpScheduler.cancel(getApplication(), task)
        }
    }

    fun toggleDone(task: TaskEntity) {
        viewModelScope.launch {
            val nowDone = !task.isDone
            val updated = task.copy(isDone = nowDone, completedAt = if (nowDone) System.currentTimeMillis() else null)
            repository.updateTask(updated)
            ReminderScheduler.schedule(getApplication(), updated)
            FollowUpScheduler.schedule(getApplication(), updated)

            // Completing a repeating task spawns the next occurrence rather than editing this
            // one in place — this one stays as done history, same as any other completed strip.
            val interval = task.repeatIntervalDays
            val dueAt = task.dueAt
            if (nowDone && interval != null && dueAt != null) {
                val nextDueAt = dueAt + interval * 24L * 60 * 60 * 1000
                val id = repository.addTask(
                    task.title, task.route, task.notes, task.priority, nextDueAt, 0,
                    emptyList(), emptyList(), emptyList(), emptyList(),
                    task.reminderMinutesBefore, interval, tags = task.tags
                )
                repository.getTask(id)?.let { ReminderScheduler.schedule(getApplication(), it) }
            }
        }
    }

    fun archiveTask(task: TaskEntity) {
        viewModelScope.launch {
            repository.archiveTask(task)
            ReminderScheduler.cancel(getApplication(), task)
            FollowUpScheduler.cancel(getApplication(), task)
        }
    }

    fun unarchiveTask(task: TaskEntity) {
        viewModelScope.launch {
            val restored = repository.unarchiveTask(task)
            ReminderScheduler.schedule(getApplication(), restored)
            FollowUpScheduler.schedule(getApplication(), restored)
        }
    }

    fun reorder(orderedActiveTasks: List<TaskEntity>) {
        viewModelScope.launch { repository.reorder(orderedActiveTasks) }
    }

    suspend fun getTask(id: Long): TaskEntity? = repository.getTask(id)
}

class TaskViewModelFactory(
    private val application: Application,
    private val repository: TaskRepository
) : ViewModelProvider.Factory {
    override fun <T : androidx.lifecycle.ViewModel> create(modelClass: Class<T>): T {
        @Suppress("UNCHECKED_CAST")
        return TaskViewModel(application, repository) as T
    }
}
