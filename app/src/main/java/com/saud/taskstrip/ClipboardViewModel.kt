package com.saud.taskstrip

import android.app.Application
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.saud.taskstrip.data.ClipboardEntity
import com.saud.taskstrip.data.ClipboardRepository
import com.saud.taskstrip.network.ClipboardSyncResult
import com.saud.taskstrip.network.ClipboardSyncSender
import com.saud.taskstrip.network.ClipboardSyncStore
import kotlinx.coroutines.flow.MutableStateFlow
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

    var syncEnabled by mutableStateOf(ClipboardSyncStore.isEnabled(application))
        private set
    var pairingCodeSet by mutableStateOf(!ClipboardSyncStore.getPairingCode(application).isNullOrBlank())
        private set

    // One-shot feedback for the last send attempt (auto or manual) — null once the UI has shown
    // and dismissed it, so rotating the screen doesn't replay a stale toast.
    private val _syncMessage = MutableStateFlow<String?>(null)
    val syncMessage: StateFlow<String?> = _syncMessage

    fun setSyncSettings(enabled: Boolean, pairingCode: String) {
        ClipboardSyncStore.setEnabled(getApplication(), enabled)
        if (pairingCode.isNotBlank()) ClipboardSyncStore.setPairingCode(getApplication(), pairingCode)
        syncEnabled = enabled
        pairingCodeSet = pairingCode.isNotBlank() || pairingCodeSet
    }

    fun dismissSyncMessage() {
        _syncMessage.value = null
    }

    /** Fire-and-forget push to whatever desktop answers on the LAN right now — failures only
     * surface as a brief status message, never block the caller, since sync is a best-effort
     * bonus on top of the local-first clipboard. */
    private fun trySync(text: String, label: String) {
        if (!syncEnabled) return
        viewModelScope.launch {
            val result = ClipboardSyncSender.send(getApplication(), text, label)
            _syncMessage.value = when (result) {
                is ClipboardSyncResult.Sent -> "Sent to ${result.deviceName}"
                is ClipboardSyncResult.NotFound -> "Desktop not found on this network"
                is ClipboardSyncResult.NotConfigured -> null
                is ClipboardSyncResult.Failed -> "Desktop sync failed: ${result.reason}"
            }
        }
    }

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
        val trimmedText = text.trim()
        val trimmedLabel = label.trim()
        viewModelScope.launch { repository.add(trimmedText, trimmedLabel) }
        trySync(trimmedText, trimmedLabel)
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

    /** Marks an item local-only (or syncable again) — set once desktop sync actually exists. */
    fun toggleSyncable(item: ClipboardEntity) {
        viewModelScope.launch { repository.update(item.copy(isSyncable = !item.isSyncable)) }
    }

    /** Re-pushes an existing item on demand — useful when it was added before the desktop was
     * reachable, or was local-only and has since been made syncable again. */
    fun sendNow(item: ClipboardEntity) {
        if (!item.isSyncable) return
        trySync(item.text, item.label)
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
