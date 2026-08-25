package com.saud.taskstrip

import android.app.Application
import android.net.Uri
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
     * lands in — anything not image/video is treated as a document. */
    fun addFromUri(uri: Uri, mimeType: String?, displayName: String?) {
        viewModelScope.launch {
            val context = getApplication<Application>()
            val (type, path) = when {
                mimeType?.startsWith("image/") == true ->
                    StorageItemType.IMAGE to MediaStorage.copyImageToLocal(context, uri)
                mimeType?.startsWith("video/") == true ->
                    StorageItemType.VIDEO to MediaStorage.copyVideoToLocal(context, uri)
                else ->
                    StorageItemType.DOCUMENT to MediaStorage.copyDocumentToLocal(context, uri)
            }
            if (path == null) return@launch
            val name = displayName ?: MediaStorage.queryDisplayName(context, uri) ?: File(path).name
            val size = runCatching { File(path).length() }.getOrDefault(0)
            repository.add(name = name, path = path, type = type, mimeType = mimeType.orEmpty(), sizeBytes = size)
        }
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
