package com.saud.taskstrip.backup

import android.app.Application
import android.content.Intent
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.google.android.gms.auth.api.signin.GoogleSignInAccount
import com.saud.taskstrip.data.AppDatabase
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class BackupUiState(
    val account: GoogleSignInAccount? = null,
    val isBusy: Boolean = false,
    val busyMessage: String = "",
    val backups: List<DriveBackupFile> = emptyList(),
    val errorMessage: String? = null,
    val lastActionSucceeded: String? = null,
    val backupPassphraseSet: Boolean = false,
    val autoBackupEnabled: Boolean = false
)

class BackupViewModel(application: Application) : AndroidViewModel(application) {
    private val taskDao = AppDatabase.getInstance(application).taskDao()
    private val credentialDao = AppDatabase.getInstance(application).credentialDao()
    private val noteDao = AppDatabase.getInstance(application).noteDao()
    private val reminderDao = AppDatabase.getInstance(application).reminderDao()
    private val storageItemDao = AppDatabase.getInstance(application).storageItemDao()

    private val _uiState = MutableStateFlow(BackupUiState())
    val uiState: StateFlow<BackupUiState> = _uiState.asStateFlow()

    init {
        val account = DriveAuthHelper.signedInAccount(getApplication())
        _uiState.value = _uiState.value.copy(
            account = account,
            backupPassphraseSet = BackupPassphraseStore.isSet(getApplication()),
            autoBackupEnabled = AutoBackupPrefs.isEnabled(getApplication())
        )
        if (account != null) refreshBackups()
    }

    fun onSignInResult(data: Intent?) {
        val context = getApplication<Application>()
        val account = DriveAuthHelper.accountFromSignInResult(context, data)
        if (account == null) {
            _uiState.value = _uiState.value.copy(errorMessage = "Google sign-in was cancelled or failed")
            return
        }
        _uiState.value = _uiState.value.copy(account = account, errorMessage = null)
        // No need to wait for the next cold start to start protecting the user's data.
        if (_uiState.value.autoBackupEnabled) AutoBackupScheduler.scheduleNext(context)
        refreshBackups()
    }

    fun setBackupPassphrase(passphrase: String) {
        BackupPassphraseStore.set(getApplication(), passphrase)
        _uiState.value = _uiState.value.copy(backupPassphraseSet = true)
    }

    fun clearBackupPassphrase() {
        BackupPassphraseStore.clear(getApplication())
        _uiState.value = _uiState.value.copy(backupPassphraseSet = false)
    }

    fun setAutoBackupEnabled(enabled: Boolean) {
        val context = getApplication<Application>()
        AutoBackupPrefs.setEnabled(context, enabled)
        _uiState.value = _uiState.value.copy(autoBackupEnabled = enabled)
        if (enabled) AutoBackupScheduler.scheduleNext(context) else AutoBackupScheduler.cancel(context)
    }

    fun signOut() {
        DriveAuthHelper.signOut(getApplication())
        _uiState.value = BackupUiState()
    }

    fun refreshBackups() {
        val account = _uiState.value.account ?: return
        viewModelScope.launch { loadBackups(account) }
    }

    /** Pulled out of [refreshBackups] so [restoreLatest] can wait for the list rather than fire a
     * refresh and hope it lands first. */
    private suspend fun loadBackups(account: GoogleSignInAccount): List<DriveBackupFile> {
        _uiState.value = _uiState.value.copy(isBusy = true, busyMessage = "Loading backups…")
        val context = getApplication<Application>()
        val token = DriveAuthHelper.getAccessToken(context, account)
        if (token == null) {
            _uiState.value = _uiState.value.copy(isBusy = false, errorMessage = "Couldn't reach Google Drive")
            return emptyList()
        }
        val folderId = DriveApi.ensureBackupFolder(token)
        val backups = if (folderId != null) DriveApi.listBackups(token, folderId) else emptyList()
        _uiState.value = _uiState.value.copy(isBusy = false, backups = backups)
        return backups
    }

    /** Signed in, or an explanation.
     *
     * The quick actions are one tap from the board's menu, so there is no screen in front of them
     * to have already said this. Doing nothing at all — which is what the screen's own buttons do
     * when signed out, since the screen shows the state anyway — would just look broken. */
    private fun requireAccount(): GoogleSignInAccount? {
        val account = _uiState.value.account
        if (account == null) {
            _uiState.value = _uiState.value.copy(
                errorMessage = "Sign in to Google Drive first — open Backup & Restore."
            )
        }
        return account
    }

    /** A backup, straight from the menu. */
    fun quickBackup() {
        if (requireAccount() == null) return
        performBackup()
    }

    /** The newest backup on Drive, restored without going through the list.
     *
     * Loads the list first when it hasn't been loaded yet: the board's menu can be opened before
     * the backup screen ever has, and "there are no backups" and "nobody has looked yet" are not
     * the same answer to give somebody about to replace everything they have.
     */
    fun restoreLatest() {
        val account = requireAccount() ?: return
        viewModelScope.launch {
            val backups = _uiState.value.backups.ifEmpty { loadBackups(account) }
            val newest = backups.firstOrNull()
            if (newest == null) {
                _uiState.value = _uiState.value.copy(errorMessage = "No backups found on Drive.")
                return@launch
            }
            performRestore(newest)
        }
    }

    /** What [restoreLatest] would replace everything with, for the confirmation to name. Null when
     * the list hasn't been loaded, which the menu treats as "the newest one" rather than lying. */
    val latestBackupName: String?
        get() = _uiState.value.backups.firstOrNull()?.name

    /** Shared by [performBackup] and [backupThenSignOut] — uploads a fresh backup and reports
     * success/failure into [_uiState], but leaves isBusy/refreshBackups to the caller since the
     * two flows do different things after a successful upload. */
    private suspend fun uploadBackup(account: GoogleSignInAccount): Boolean {
        val context = getApplication<Application>()
        val token = DriveAuthHelper.getAccessToken(context, account)
        if (token == null) {
            _uiState.value = _uiState.value.copy(errorMessage = "Couldn't reach Google Drive")
            return false
        }
        val folderId = DriveApi.ensureBackupFolder(token)
        if (folderId == null) {
            _uiState.value = _uiState.value.copy(errorMessage = "Couldn't prepare the Drive backup folder")
            return false
        }
        val passphrase = BackupPassphraseStore.get(context)
        val zip = BackupHelper.createBackupZip(context, taskDao, credentialDao, noteDao, reminderDao, storageItemDao, passphrase)
        val uploaded = DriveApi.uploadBackup(token, folderId, zip, BackupHelper.backupFileName())
        zip.delete()
        if (!uploaded) {
            _uiState.value = _uiState.value.copy(errorMessage = "Backup upload failed")
        }
        return uploaded
    }

    fun performBackup() {
        val account = _uiState.value.account ?: return
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isBusy = true, busyMessage = "Backing up…", errorMessage = null, lastActionSucceeded = null)
            if (uploadBackup(account)) {
                val passphrase = BackupPassphraseStore.get(getApplication())
                val note = if (credentialDao.getAllOnce().isNotEmpty() && passphrase == null) {
                    " (credential passwords skipped — set a backup passphrase to include them)"
                } else {
                    ""
                }
                _uiState.value = _uiState.value.copy(isBusy = false, lastActionSucceeded = "Backup uploaded to Drive$note")
                refreshBackups()
            } else {
                _uiState.value = _uiState.value.copy(isBusy = false)
            }
        }
    }

    /** Backs up before signing out, so the user isn't left without a safety net if they don't
     * sign back in on this device — only actually signs out once the upload succeeds; a failure
     * leaves them signed in (with the error shown) so they can retry. */
    fun backupThenSignOut() {
        val account = _uiState.value.account ?: return
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isBusy = true, busyMessage = "Backing up before sign out…", errorMessage = null, lastActionSucceeded = null)
            if (uploadBackup(account)) {
                signOut()
            } else {
                _uiState.value = _uiState.value.copy(isBusy = false)
            }
        }
    }

    /** [restorePassphrase] overrides the locally stored one when given (e.g. the user typed one in
     * because this device has never had it set) — falls back to the stored passphrase otherwise. */
    fun performRestore(file: DriveBackupFile, restorePassphrase: String? = null) {
        val account = _uiState.value.account ?: return
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isBusy = true, busyMessage = "Restoring…", errorMessage = null, lastActionSucceeded = null)
            val context = getApplication<Application>()
            val token = DriveAuthHelper.getAccessToken(context, account)
            if (token == null) {
                _uiState.value = _uiState.value.copy(isBusy = false, errorMessage = "Couldn't reach Google Drive")
                return@launch
            }
            val zip = java.io.File(context.cacheDir, "restore_${file.id}.zip")
            val downloaded = DriveApi.downloadBackup(token, file.id, zip)
            if (!downloaded) {
                _uiState.value = _uiState.value.copy(isBusy = false, errorMessage = "Couldn't download that backup")
                return@launch
            }
            try {
                val passphrase = restorePassphrase ?: BackupPassphraseStore.get(context)
                val result = BackupHelper.restoreFromZip(context, zip, taskDao, credentialDao, noteDao, reminderDao, storageItemDao, passphrase)
                val message = if (result.credentialPasswordsFailed > 0) {
                    val restoredNote = if (result.credentialPasswordsRestored > 0) "${result.credentialPasswordsRestored} restored, " else ""
                    "Restored \"${file.name}\" — but $restoredNote${result.credentialPasswordsFailed} credential password(s) couldn't be decrypted (wrong or missing backup passphrase)"
                } else {
                    "Restored \"${file.name}\""
                }
                _uiState.value = _uiState.value.copy(isBusy = false, lastActionSucceeded = message)
            } catch (e: Exception) {
                _uiState.value = _uiState.value.copy(isBusy = false, errorMessage = "Restore failed: that file may be corrupted")
            } finally {
                zip.delete()
            }
        }
    }

    fun dismissMessages() {
        _uiState.value = _uiState.value.copy(errorMessage = null, lastActionSucceeded = null)
    }
}

class BackupViewModelFactory(private val application: Application) : ViewModelProvider.Factory {
    override fun <T : androidx.lifecycle.ViewModel> create(modelClass: Class<T>): T {
        @Suppress("UNCHECKED_CAST")
        return BackupViewModel(application) as T
    }
}
