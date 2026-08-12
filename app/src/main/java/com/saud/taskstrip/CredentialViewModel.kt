package com.saud.taskstrip

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.saud.taskstrip.data.CredentialEntity
import com.saud.taskstrip.data.CredentialRepository
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

class CredentialViewModel(
    application: Application,
    private val repository: CredentialRepository
) : AndroidViewModel(application) {

    val credentials: StateFlow<List<CredentialEntity>> = repository.credentials
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    fun add(title: String, username: String, password: String, url: String, notes: String) {
        viewModelScope.launch { repository.add(title, username, password, url, notes) }
    }

    fun update(existing: CredentialEntity, title: String, username: String, password: String, url: String, notes: String) {
        viewModelScope.launch { repository.update(existing, title, username, password, url, notes) }
    }

    fun delete(credential: CredentialEntity) {
        viewModelScope.launch { repository.delete(credential) }
    }

    suspend fun getById(id: Long): CredentialEntity? = repository.getById(id)

    fun decryptPassword(credential: CredentialEntity): String = repository.decryptPassword(credential)
}

class CredentialViewModelFactory(
    private val application: Application,
    private val repository: CredentialRepository
) : ViewModelProvider.Factory {
    override fun <T : androidx.lifecycle.ViewModel> create(modelClass: Class<T>): T {
        @Suppress("UNCHECKED_CAST")
        return CredentialViewModel(application, repository) as T
    }
}
