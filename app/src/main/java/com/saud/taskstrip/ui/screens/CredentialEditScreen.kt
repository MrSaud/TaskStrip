package com.saud.taskstrip.ui.screens

import android.widget.Toast
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Fingerprint
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LocalTextStyle
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import androidx.fragment.app.FragmentActivity
import com.saud.taskstrip.CredentialViewModel
import com.saud.taskstrip.data.CredentialEntity
import com.saud.taskstrip.security.BiometricAuthHelper
import com.saud.taskstrip.ui.theme.AmberTab
import com.saud.taskstrip.ui.theme.BayBackground
import com.saud.taskstrip.ui.theme.Paper
import com.saud.taskstrip.ui.theme.PriorityUrgent
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CredentialEditScreen(
    viewModel: CredentialViewModel,
    credentialId: Long,
    onDone: () -> Unit
) {
    val context = LocalContext.current
    val activity = context as? FragmentActivity
    val scope = rememberCoroutineScope()
    val isEditing = credentialId >= 0

    var title by rememberSaveable { mutableStateOf("") }
    var username by rememberSaveable { mutableStateOf("") }
    // Starts blank in edit mode on purpose — the real password is never shown without a
    // biometric reveal, and a blank value on save means "leave the stored password unchanged".
    var password by rememberSaveable { mutableStateOf("") }
    var passwordVisible by rememberSaveable { mutableStateOf(false) }
    var passwordRevealed by rememberSaveable { mutableStateOf(false) }
    var url by rememberSaveable { mutableStateOf("") }
    var notes by rememberSaveable { mutableStateOf("") }
    var showDeleteConfirm by rememberSaveable { mutableStateOf(false) }
    var loadedCredential by remember { mutableStateOf<CredentialEntity?>(null) }

    LaunchedEffect(credentialId) {
        if (isEditing) {
            viewModel.getById(credentialId)?.let { c ->
                loadedCredential = c
                title = c.title
                username = c.username
                url = c.url
                notes = c.notes
            }
        }
    }

    Scaffold(
        containerColor = BayBackground,
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        text = if (isEditing) "EDIT CREDENTIAL" else "NEW CREDENTIAL",
                        style = MaterialTheme.typography.titleLarge,
                        color = Paper
                    )
                },
                navigationIcon = {
                    IconButton(onClick = onDone) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back", tint = Paper)
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = BayBackground)
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .padding(padding)
                .padding(20.dp)
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
        ) {
            OutlinedTextField(
                value = title,
                onValueChange = { title = it },
                label = { Text("TITLE") },
                singleLine = true,
                textStyle = LocalTextStyle.current.copy(fontFamily = FontFamily.Monospace),
                modifier = Modifier.fillMaxWidth()
            )
            Spacer(Modifier.height(14.dp))
            OutlinedTextField(
                value = username,
                onValueChange = { username = it },
                label = { Text("USERNAME") },
                singleLine = true,
                textStyle = LocalTextStyle.current.copy(fontFamily = FontFamily.Monospace),
                modifier = Modifier.fillMaxWidth()
            )
            Spacer(Modifier.height(14.dp))
            OutlinedTextField(
                value = password,
                onValueChange = { password = it },
                label = { Text(if (isEditing && !passwordRevealed) "PASSWORD (unchanged)" else "PASSWORD") },
                singleLine = true,
                visualTransformation = if (passwordVisible) VisualTransformation.None else PasswordVisualTransformation(),
                textStyle = LocalTextStyle.current.copy(fontFamily = FontFamily.Monospace),
                trailingIcon = {
                    if (isEditing && !passwordRevealed) {
                        IconButton(onClick = {
                            val existing = loadedCredential ?: return@IconButton
                            if (activity == null) return@IconButton
                            scope.launch {
                                val ok = BiometricAuthHelper.authenticate(
                                    activity, "Unlock credential", "Confirm your identity to view the stored password"
                                )
                                if (ok) {
                                    password = viewModel.decryptPassword(existing)
                                    passwordRevealed = true
                                    passwordVisible = true
                                } else {
                                    Toast.makeText(context, "Authentication required", Toast.LENGTH_SHORT).show()
                                }
                            }
                        }) {
                            Icon(Icons.Default.Fingerprint, contentDescription = "Reveal current password", tint = Paper.copy(alpha = 0.7f))
                        }
                    } else {
                        IconButton(onClick = { passwordVisible = !passwordVisible }) {
                            Icon(
                                imageVector = if (passwordVisible) Icons.Default.VisibilityOff else Icons.Default.Visibility,
                                contentDescription = if (passwordVisible) "Hide password" else "Show password",
                                tint = Paper.copy(alpha = 0.7f)
                            )
                        }
                    }
                },
                modifier = Modifier.fillMaxWidth()
            )
            Spacer(Modifier.height(14.dp))
            OutlinedTextField(
                value = url,
                onValueChange = { url = it },
                label = { Text("URL (optional)") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri),
                textStyle = LocalTextStyle.current.copy(fontFamily = FontFamily.Monospace),
                modifier = Modifier.fillMaxWidth()
            )
            Spacer(Modifier.height(14.dp))
            OutlinedTextField(
                value = notes,
                onValueChange = { notes = it },
                label = { Text("NOTES") },
                textStyle = LocalTextStyle.current.copy(fontFamily = FontFamily.Monospace),
                modifier = Modifier.fillMaxWidth().height(120.dp)
            )
            Spacer(Modifier.height(28.dp))
            Button(
                onClick = {
                    if (title.isNotBlank()) {
                        val existing = loadedCredential
                        if (isEditing && existing != null) {
                            viewModel.update(existing, title.trim(), username.trim(), password, url.trim(), notes.trim())
                        } else {
                            viewModel.add(title.trim(), username.trim(), password, url.trim(), notes.trim())
                        }
                        onDone()
                    }
                },
                colors = ButtonDefaults.buttonColors(containerColor = AmberTab, contentColor = Paper),
                modifier = Modifier.fillMaxWidth().height(52.dp)
            ) {
                Text(
                    text = if (isEditing) "UPDATE CREDENTIAL" else "SAVE CREDENTIAL",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold
                )
            }
            if (isEditing) {
                Spacer(Modifier.height(10.dp))
                OutlinedButton(
                    onClick = { showDeleteConfirm = true },
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text("DELETE CREDENTIAL", color = PriorityUrgent, style = MaterialTheme.typography.bodyLarge)
                }
            }
        }
    }

    if (showDeleteConfirm) {
        AlertDialog(
            onDismissRequest = { showDeleteConfirm = false },
            title = { Text("DELETE CREDENTIAL?", style = MaterialTheme.typography.titleMedium) },
            text = { Text("\"${title.ifBlank { "This credential" }}\" will be permanently deleted. This can't be undone.") },
            confirmButton = {
                TextButton(onClick = {
                    showDeleteConfirm = false
                    loadedCredential?.let { viewModel.delete(it) }
                    onDone()
                }) { Text("DELETE", color = PriorityUrgent) }
            },
            dismissButton = {
                TextButton(onClick = { showDeleteConfirm = false }) { Text("CANCEL") }
            }
        )
    }
}
