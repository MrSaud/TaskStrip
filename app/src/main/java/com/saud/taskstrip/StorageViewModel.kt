package com.saud.taskstrip

import android.app.Application
import android.net.Uri
import android.webkit.MimeTypeMap
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.saud.taskstrip.data.StorageItemEntity
import com.saud.taskstrip.data.StorageItemType
import com.saud.taskstrip.data.StorageRepository
import com.saud.taskstrip.media.MediaStorage
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import java.io.File

class StorageViewModel(
    application: Application,
    private val repository: StorageRepository
) : AndroidViewModel(application) {

    val items: StateFlow<List<StorageItemEntity>> = repository.items
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    /** Copies a picked image/video/document into the library. [mimeType] drives which category it
     * lands in — anything not image/video is treated as a document.
     *
     * Some senders (share sheets in particular) report a useless MIME type — null, a wildcard, or
     * "application/octet-stream" — for a perfectly normal photo or video. Trusting that blindly
     * would silently file it under Documents, where it never appears when a strip's "add from
     * storage" picker is filtered to Photos or Videos, even though it's sitting right there in
     * the library. Falling back to the file extension when the reported type is unhelpful keeps
     * it in the category the user actually expects. */
    fun addFromUri(uri: Uri, mimeType: String?, displayName: String?) {
        viewModelScope.launch {
            val context = getApplication<Application>()
            val name = displayName ?: MediaStorage.queryDisplayName(context, uri)
            val resolvedMimeType = resolveMimeType(mimeType, name)
            val (type, path) = when {
                resolvedMimeType?.startsWith("image/") == true ->
                    StorageItemType.IMAGE to MediaStorage.copyImageToLocal(context, uri)
                resolvedMimeType?.startsWith("video/") == true ->
                    StorageItemType.VIDEO to MediaStorage.copyVideoToLocal(context, uri)
                else ->
                    StorageItemType.DOCUMENT to MediaStorage.copyDocumentToLocal(context, uri)
            }
            if (path == null) return@launch
            val finalName = name ?: File(path).name
            val size = runCatching { File(path).length() }.getOrDefault(0)
            repository.add(name = finalName, path = path, type = type, mimeType = resolvedMimeType.orEmpty(), sizeBytes = size)
        }
    }

    private fun resolveMimeType(reported: String?, displayName: String?): String? {
        val isUseless = reported.isNullOrBlank() || reported == "*/*" || reported == "application/octet-stream"
        if (!isUseless) return reported
        val extension = displayName?.substringAfterLast('.', "")?.lowercase()?.takeIf { it.isNotBlank() }
            ?: return reported
        return MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension) ?: reported
    }

    /** Assigns (or with blank values clears) the tag used to group and filter documents. */
    fun setTag(item: StorageItemEntity, tag: String, tagEmoji: String) {
        viewModelScope.launch { repository.setTag(item, tag.trim(), tagEmoji.trim()) }
    }

    fun delete(item: StorageItemEntity) {
        viewModelScope.launch {
            if (item.type == StorageItemType.DOCUMENT) {
                MediaStorage.deleteDocument(item.path)
            } else {
                MediaStorage.deleteFile(item.path)
            }
            repository.delete(item)
        }
    }
}

class StorageViewModelFactory(
    private val application: Application,
    private val repository: StorageRepository
) : ViewModelProvider.Factory {
    override fun <T : androidx.lifecycle.ViewModel> create(modelClass: Class<T>): T {
        @Suppress("UNCHECKED_CAST")
        return StorageViewModel(application, repository) as T
    }
}
