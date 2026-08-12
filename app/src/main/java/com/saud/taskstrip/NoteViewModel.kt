package com.saud.taskstrip

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.saud.taskstrip.data.NoteEntity
import com.saud.taskstrip.data.NoteRepository
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

class NoteViewModel(
    application: Application,
    private val repository: NoteRepository
) : AndroidViewModel(application) {

    val notes: StateFlow<List<NoteEntity>> = repository.notes
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    fun add(text: String) {
        if (text.isBlank()) return
        viewModelScope.launch { repository.add(text.trim()) }
    }

    fun delete(note: NoteEntity) {
        viewModelScope.launch { repository.delete(note) }
    }
}

class NoteViewModelFactory(
    private val application: Application,
    private val repository: NoteRepository
) : ViewModelProvider.Factory {
    override fun <T : androidx.lifecycle.ViewModel> create(modelClass: Class<T>): T {
        @Suppress("UNCHECKED_CAST")
        return NoteViewModel(application, repository) as T
    }
}
