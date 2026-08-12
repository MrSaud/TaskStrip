package com.saud.taskstrip.ui.screens

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.CloudUpload
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Restore
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.saud.taskstrip.backup.BackupViewModel
import com.saud.taskstrip.backup.DriveAuthHelper
import com.saud.taskstrip.backup.DriveBackupFile
import com.saud.taskstrip.ui.theme.AmberTab
import com.saud.taskstrip.ui.theme.BayBackground
import com.saud.taskstrip.ui.theme.BaySurface
import com.saud.taskstrip.ui.theme.InkColor
import com.saud.taskstrip.ui.theme.Paper
import com.saud.taskstrip.ui.theme.PriorityUrgent
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BackupScreen(
    viewModel: BackupViewModel,
    onBack: () -> Unit
) {
    val context = LocalContext.current
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    var pendingRestore by remember { mutableStateOf<DriveBackupFile?>(null) }
    var restorePassphraseInput by remember { mutableStateOf("") }
    var showPassphraseDialog by remember { mutableStateOf(false) }

    val signInLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.StartActivityForResult()
    ) { result -> viewModel.onSignInResult(result.data) }

    Scaffold(
        containerColor = BayBackground,
        topBar = {
            TopAppBar(
                title = { Text("BACKUP & RESTORE", style = MaterialTheme.typography.titleLarge, color = Paper) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back", tint = Paper)
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = BayBackground)
            )
        }
    ) { padding ->
        Column(
            Modifier
                .padding(padding)
                .padding(20.dp)
                .fillMaxSize()
        ) {
            val account = state.account
            if (account == null) {
                Text(
                    text = "Sign in with Google to back up your strips, credentials, and attachments to Drive, and restore them on any device.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = Paper.copy(alpha = 0.7f)
                )
                Spacer(Modifier.height(20.dp))
                Button(
                    onClick = { signInLauncher.launch(DriveAuthHelper.signInIntent(context)) },
                    colors = ButtonDefaults.buttonColors(containerColor = AmberTab, contentColor = InkColor),
                    modifier = Modifier.fillMaxWidth().height(52.dp)
                ) {
                    Text("SIGN IN WITH GOOGLE", style = MaterialTheme.typography.titleMedium)
                }
            } else {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        text = account.email ?: "Signed in",
                        style = MaterialTheme.typography.bodyMedium,
                        color = Paper.copy(alpha = 0.8f),
                        modifier = Modifier.weight(1f)
                    )
                    TextButton(onClick = { viewModel.signOut() }) {
                        Text("SIGN OUT", color = Paper.copy(alpha = 0.6f))
                    }
                }
                Spacer(Modifier.height(14.dp))
                Button(
                    onClick = { viewModel.performBackup() },
                    enabled = !state.isBusy,
                    colors = ButtonDefaults.buttonColors(containerColor = AmberTab, contentColor = InkColor),
                    modifier = Modifier.fillMaxWidth().height(52.dp)
                ) {
                    Icon(Icons.Default.CloudUpload, contentDescription = null)
                    Spacer(Modifier.width(8.dp))
                    Text("BACK UP NOW", style = MaterialTheme.typography.titleMedium)
                }

                Spacer(Modifier.height(20.dp))
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Column(Modifier.weight(1f)) {
                        Text("AUTO BACKUP DAILY", style = MaterialTheme.typography.bodyMedium, color = Paper)
                        Text(
                            "Backs up automatically overnight, around 3 AM",
                            style = MaterialTheme.typography.labelSmall,
                            color = Paper.copy(alpha = 0.5f)
                        )
                    }
                    Switch(
                        checked = state.autoBackupEnabled,
                        onCheckedChange = { viewModel.setAutoBackupEnabled(it) },
                        colors = SwitchDefaults.colors(checkedTrackColor = AmberTab)
                    )
                }

                Spacer(Modifier.height(14.dp))
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Icon(Icons.Default.Lock, contentDescription = null, tint = Paper.copy(alpha = 0.7f))
                    Spacer(Modifier.width(10.dp))
                    Column(Modifier.weight(1f)) {
                        Text("CREDENTIAL PASSWORD ENCRYPTION", style = MaterialTheme.typography.bodyMedium, color = Paper)
                        Text(
                            text = if (state.backupPassphraseSet) {
                                "Backup passphrase is set — credential passwords are included, encrypted"
                            } else {
                                "Not set — credential passwords are left out of backups"
                            },
                            style = MaterialTheme.typography.labelSmall,
                            color = Paper.copy(alpha = 0.5f)
                        )
                    }
                    TextButton(onClick = { showPassphraseDialog = true }) {
                        Text(if (state.backupPassphraseSet) "CHANGE" else "SET", color = AmberTab)
                    }
                }

                Spacer(Modifier.height(24.dp))
                Text("BACKUPS ON DRIVE", style = MaterialTheme.typography.labelSmall, color = Paper.copy(alpha = 0.7f))
                Spacer(Modifier.height(8.dp))

                if (state.isBusy) {
                    Box(Modifier.fillMaxWidth().padding(vertical = 24.dp), contentAlignment = Alignment.Center) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            CircularProgressIndicator(color = AmberTab)
                            Spacer(Modifier.height(8.dp))
                            Text(state.busyMessage, color = Paper.copy(alpha = 0.6f), style = MaterialTheme.typography.bodyMedium)
                        }
                    }
                } else if (state.backups.isEmpty()) {
                    Text(
                        text = "No backups yet",
                        style = MaterialTheme.typography.bodyMedium,
                        color = Paper.copy(alpha = 0.5f)
                    )
                } else {
                    LazyColumn(Modifier.fillMaxSize()) {
                        items(state.backups, key = { it.id }) { file ->
                            BackupRow(
                                file = file,
                                onRestoreClick = {
                                    restorePassphraseInput = ""
                                    pendingRestore = file
                                }
                            )
                            Spacer(Modifier.height(8.dp))
                        }
                    }
                }
            }
        }
    }

    state.errorMessage?.let { message ->
        AlertDialog(
            onDismissRequest = { viewModel.dismissMessages() },
            title = { Text("SOMETHING WENT WRONG", style = MaterialTheme.typography.titleMedium) },
            text = { Text(message) },
            confirmButton = {
                TextButton(onClick = { viewModel.dismissMessages() }) { Text("OK") }
            }
        )
    }

    state.lastActionSucceeded?.let { message ->
        AlertDialog(
            onDismissRequest = { viewModel.dismissMessages() },
            title = { Text("DONE", style = MaterialTheme.typography.titleMedium) },
            text = { Text(message) },
            confirmButton = {
                TextButton(onClick = { viewModel.dismissMessages() }) { Text("OK") }
            }
        )
    }

    if (showPassphraseDialog) {
        SetPassphraseDialog(
            onDismiss = { showPassphraseDialog = false },
            onConfirm = { passphrase ->
                viewModel.setBackupPassphrase(passphrase)
                showPassphraseDialog = false
            },
            onRemove = if (state.backupPassphraseSet) {
                {
                    viewModel.clearBackupPassphrase()
                    showPassphraseDialog = false
                }
            } else {
                null
            }
        )
    }

    pendingRestore?.let { file ->
        AlertDialog(
            onDismissRequest = { pendingRestore = null },
            title = { Text("RESTORE FROM BACKUP?", style = MaterialTheme.typography.titleMedium) },
            text = {
                Column {
                    Text(
                        "This replaces every strip and credential currently on this device with the contents of \"${file.name}\". This can't be undone."
                    )
                    if (!state.backupPassphraseSet) {
                        Spacer(Modifier.height(14.dp))
                        Text(
                            "If this backup has encrypted credential passwords, enter the backup passphrase to restore them (leave blank to skip):",
                            style = MaterialTheme.typography.bodySmall
                        )
                        Spacer(Modifier.height(6.dp))
                        OutlinedTextField(
                            value = restorePassphraseInput,
                            onValueChange = { restorePassphraseInput = it },
                            label = { Text("BACKUP PASSPHRASE (optional)") },
                            singleLine = true,
                            visualTransformation = PasswordVisualTransformation(),
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                            modifier = Modifier.fillMaxWidth()
                        )
                    }
                }
            },
            confirmButton = {
                TextButton(onClick = {
                    viewModel.performRestore(file, restorePassphraseInput.ifBlank { null })
                    pendingRestore = null
                }) { Text("RESTORE", color = PriorityUrgent) }
            },
            dismissButton = {
                TextButton(onClick = { pendingRestore = null }) { Text("CANCEL") }
            }
        )
    }
}

@Composable
private fun SetPassphraseDialog(
    onDismiss: () -> Unit,
    onConfirm: (String) -> Unit,
    onRemove: (() -> Unit)?
) {
    var passphrase by remember { mutableStateOf("") }
    var confirmPassphrase by remember { mutableStateOf("") }
    val mismatch = confirmPassphrase.isNotEmpty() && passphrase != confirmPassphrase

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("BACKUP PASSPHRASE", style = MaterialTheme.typography.titleMedium) },
        text = {
            Column {
                Text(
                    "Used to encrypt credential passwords inside backups. Write it down somewhere safe — " +
                        "it's not stored anywhere recoverable, and without it those passwords can't be restored on a new device.",
                    style = MaterialTheme.typography.bodySmall
                )
                Spacer(Modifier.height(14.dp))
                OutlinedTextField(
                    value = passphrase,
                    onValueChange = { passphrase = it },
                    label = { Text("PASSPHRASE") },
                    singleLine = true,
                    visualTransformation = PasswordVisualTransformation(),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                    modifier = Modifier.fillMaxWidth()
                )
                Spacer(Modifier.height(8.dp))
                OutlinedTextField(
                    value = confirmPassphrase,
                    onValueChange = { confirmPassphrase = it },
                    label = { Text("CONFIRM PASSPHRASE") },
                    singleLine = true,
                    isError = mismatch,
                    visualTransformation = PasswordVisualTransformation(),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                    modifier = Modifier.fillMaxWidth()
                )
                if (mismatch) {
                    Text("Doesn't match", color = PriorityUrgent, style = MaterialTheme.typography.labelSmall)
                }
                if (onRemove != null) {
                    Spacer(Modifier.height(10.dp))
                    TextButton(onClick = onRemove) {
                        Text("REMOVE PASSPHRASE (stop encrypting credentials in backups)", color = PriorityUrgent)
                    }
                }
            }
        },
        confirmButton = {
            TextButton(
                enabled = passphrase.isNotBlank() && passphrase == confirmPassphrase,
                onClick = { onConfirm(passphrase) }
            ) { Text("SAVE", color = AmberTab) }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("CANCEL") }
        }
    )
}

@Composable
private fun BackupRow(file: DriveBackupFile, onRestoreClick: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(BaySurface, RoundedCornerShape(4.dp))
            .padding(16.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(Modifier.weight(1f)) {
            Text(
                text = formatDriveTimestamp(file.createdTime),
                style = MaterialTheme.typography.bodyMedium,
                color = Paper,
                fontFamily = FontFamily.Monospace
            )
            Text(
                text = formatFileSize(file.size),
                style = MaterialTheme.typography.labelSmall,
                color = Paper.copy(alpha = 0.5f)
            )
        }
        OutlinedButton(onClick = onRestoreClick) {
            Icon(Icons.Default.Restore, contentDescription = null, modifier = Modifier.width(18.dp))
            Spacer(Modifier.width(6.dp))
            Text("RESTORE")
        }
    }
}

private fun formatDriveTimestamp(iso: String): String = try {
    Instant.parse(iso).atZone(ZoneId.systemDefault())
        .format(DateTimeFormatter.ofPattern("dd MMM yyyy, HH:mm"))
} catch (e: Exception) {
    iso
}

private fun formatFileSize(bytes: Long): String = when {
    bytes >= 1024 * 1024 -> String.format(Locale.US, "%.1f MB", bytes / (1024.0 * 1024.0))
    bytes >= 1024 -> String.format(Locale.US, "%.0f KB", bytes / 1024.0)
    else -> "$bytes B"
}
