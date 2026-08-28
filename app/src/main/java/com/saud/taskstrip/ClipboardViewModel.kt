package com.saud.taskstrip

import android.app.Application
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.saud.taskstrip.data.ClipboardEntity
import com.saud.taskstrip.data.ClipboardRepository
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

class ClipboardViewModel(
    application: Application,
    private val repository: ClipboardRepository
) : AndroidViewModel(application) {

    val items: StateFlow<List<ClipboardEntity>> = repository.items
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    private fun clipboardManager(): ClipboardManager =
        getApplication<Application>().getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager

    /**
     * Reads whatever the system clipboard currently holds. Android 10+ only serves this to an app
     * that holds focus, which a button tap guarantees — the same restriction is why this feature
     * can't quietly capture copies in the background, and why it's a button in the first place.
     *
     * Returns false when the clipboard is empty or holds something with no text form, so the
     * caller can say so rather than silently storing a blank row.
     */
    fun pasteFromSystemClipboard(): Boolean {
        val clip = clipboardManager().primaryClip ?: return false
        if (clip.itemCount == 0) return false
        val text = clip.getItemAt(0).coerceToText(getApplication()).toString()
        if (text.isBlank()) return false
        add(text)
        return true
    }

    fun add(text: String, label: String = "") {
        if (text.isBlank()) return
        viewModelScope.launch { repository.add(text.trim(), label.trim()) }
    }

    /** Puts an item back on the system clipboard, ready to paste into another app. */
    fun copyToSystemClipboard(item: ClipboardEntity) {
        val label = item.label.ifBlank { "Task Strips" }
        clipboardManager().setPrimaryClip(ClipData.newPlainText(label, item.text))
    }

    fun setLabel(item: ClipboardEntity, label: String) {
        viewModelScope.launch { repository.update(item.copy(label = label.trim())) }
    }

    fun setText(item: ClipboardEntity, text: String) {
        if (text.isBlank()) return
        viewModelScope.launch { repository.update(item.copy(text = text.trim())) }
    }

    fun togglePinned(item: ClipboardEntity) {
        viewModelScope.launch { repository.update(item.copy(isPinned = !item.isPinned)) }
    }

    /** Marks an item local-only (or syncable again) ahead of the desktop transport landing. */
    fun toggleSyncable(item: ClipboardEntity) {
        viewModelScope.launch { repository.update(item.copy(isSyncable = !item.isSyncable)) }
    }

    fun delete(item: ClipboardEntity) {
        viewModelScope.launch { repository.delete(item) }
    }

    fun clearUnpinned() {
        viewModelScope.launch { repository.clearUnpinned() }
    }
}

class ClipboardViewModelFactory(
    private val application: Application,
    private val repository: ClipboardRepository
) : ViewModelProvider.Factory {
    override fun <T : androidx.lifecycle.ViewModel> create(modelClass: Class<T>): T {
        @Suppress("UNCHECKED_CAST")
        return ClipboardViewModel(application, repository) as T
    }
}
