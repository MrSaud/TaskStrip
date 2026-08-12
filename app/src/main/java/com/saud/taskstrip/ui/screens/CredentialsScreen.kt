package com.saud.taskstrip.ui.screens

import android.content.Intent
import android.widget.Toast
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Fingerprint
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExtendedFloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.runtime.LaunchedEffect
import androidx.fragment.app.FragmentActivity
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.saud.taskstrip.CredentialViewModel
import com.saud.taskstrip.data.CredentialEntity
import com.saud.taskstrip.security.BiometricAuthHelper
import com.saud.taskstrip.ui.theme.AmberTab
import com.saud.taskstrip.ui.theme.BayBackground
import com.saud.taskstrip.ui.theme.BaySurface
import com.saud.taskstrip.ui.theme.InkColor
import com.saud.taskstrip.ui.theme.Paper
import com.saud.taskstrip.ui.theme.PriorityUrgent
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CredentialsScreen(
    viewModel: CredentialViewModel,
    onBack: () -> Unit,
    onAddClick: () -> Unit,
    onEditClick: (Long) -> Unit
) {
    val credentials by viewModel.credentials.collectAsStateWithLifecycle()
    var pendingDelete by remember { mutableStateOf<CredentialEntity?>(null) }
    var searchActive by remember { mutableStateOf(false) }
    var searchQuery by remember { mutableStateOf("") }
    val searchFocusRequester = remember { FocusRequester() }

    val visibleCredentials = remember(credentials, searchQuery) {
        if (searchQuery.isBlank()) {
            credentials
        } else {
            credentials.filter { c ->
                c.title.contains(searchQuery, ignoreCase = true) ||
                    c.username.contains(searchQuery, ignoreCase = true) ||
                    c.url.contains(searchQuery, ignoreCase = true)
            }
        }
    }

    LaunchedEffect(searchActive) {
        if (searchActive) searchFocusRequester.requestFocus()
    }

    Scaffold(
        containerColor = BayBackground,
        topBar = {
            TopAppBar(
                title = {
                    if (searchActive) {
                        TextField(
                            value = searchQuery,
                            onValueChange = { searchQuery = it },
                            modifier = Modifier
                                .fillMaxWidth()
                                .focusRequester(searchFocusRequester),
                            placeholder = { Text("Search credentials…") },
                            singleLine = true,
                            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                            keyboardActions = KeyboardActions(onSearch = {}),
                            colors = TextFieldDefaults.colors(
                                focusedContainerColor = androidx.compose.ui.graphics.Color.Transparent,
                                unfocusedContainerColor = androidx.compose.ui.graphics.Color.Transparent,
                                focusedIndicatorColor = androidx.compose.ui.graphics.Color.Transparent,
                                unfocusedIndicatorColor = androidx.compose.ui.graphics.Color.Transparent,
                                cursorColor = AmberTab,
                                focusedTextColor = Paper,
                                unfocusedTextColor = Paper
                            )
                        )
                    } else {
                        Text("CREDENTIALS", style = MaterialTheme.typography.titleLarge, color = Paper)
                    }
                },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back", tint = Paper)
                    }
                },
                actions = {
                    if (searchActive) {
                        IconButton(onClick = {
                            searchActive = false
                            searchQuery = ""
                        }) {
                            Icon(Icons.Default.Close, contentDescription = "Close search", tint = Paper)
                        }
                    } else {
                        IconButton(onClick = { searchActive = true }) {
                            Icon(Icons.Default.Search, contentDescription = "Search", tint = Paper)
                        }
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = BayBackground)
            )
        },
        floatingActionButton = {
            ExtendedFloatingActionButton(
                onClick = onAddClick,
                containerColor = AmberTab,
                contentColor = InkColor,
                icon = { Icon(Icons.Default.Add, contentDescription = null) },
                text = { Text("NEW CREDENTIAL", style = MaterialTheme.typography.bodyLarge) }
            )
        }
    ) { padding ->
        if (credentials.isEmpty()) {
            Box(Modifier.padding(padding).fillMaxSize(), contentAlignment = Alignment.Center) {
                Text(
                    text = "NO CREDENTIALS STORED",
                    style = MaterialTheme.typography.titleMedium,
                    color = Paper.copy(alpha = 0.5f)
                )
            }
        } else if (visibleCredentials.isEmpty()) {
            Box(Modifier.padding(padding).fillMaxSize(), contentAlignment = Alignment.Center) {
                Text(
                    text = "NO MATCHES",
                    style = MaterialTheme.typography.titleMedium,
                    color = Paper.copy(alpha = 0.5f)
                )
            }
        } else {
            LazyColumn(
                modifier = Modifier.padding(padding).fillMaxSize(),
                contentPadding = androidx.compose.foundation.layout.PaddingValues(12.dp)
            ) {
                items(visibleCredentials, key = { it.id }) { credential ->
                    CredentialRow(
                        credential = credential,
                        viewModel = viewModel,
                        onClick = { onEditClick(credential.id) },
                        onDeleteRequest = { pendingDelete = credential }
                    )
                    Spacer(Modifier.height(10.dp))
                }
            }
        }
    }

    pendingDelete?.let { credential ->
        AlertDialog(
            onDismissRequest = { pendingDelete = null },
            title = { Text("DELETE CREDENTIAL?", style = MaterialTheme.typography.titleMedium) },
            text = { Text("\"${credential.title}\" will be permanently deleted. This can't be undone.") },
            confirmButton = {
                TextButton(onClick = {
                    viewModel.delete(credential)
                    pendingDelete = null
                }) { Text("DELETE", color = PriorityUrgent) }
            },
            dismissButton = {
                TextButton(onClick = { pendingDelete = null }) { Text("CANCEL") }
            }
        )
    }
}

@Composable
private fun CredentialRow(
    credential: CredentialEntity,
    viewModel: CredentialViewModel,
    onClick: () -> Unit,
    onDeleteRequest: () -> Unit
) {
    val context = LocalContext.current
    val activity = context as? FragmentActivity
    val scope = rememberCoroutineScope()
    val clipboard = LocalClipboardManager.current
    var revealedPassword by remember(credential.id) { mutableStateOf<String?>(null) }

    fun requestReveal(onSuccess: (String) -> Unit) {
        if (activity == null) return
        scope.launch {
            val ok = BiometricAuthHelper.authenticate(
                activity,
                "Unlock credential",
                "Confirm your identity to view \"${credential.title}\""
            )
            if (ok) {
                onSuccess(viewModel.decryptPassword(credential))
            } else {
                Toast.makeText(context, "Authentication required", Toast.LENGTH_SHORT).show()
            }
        }
    }

    Column(
        Modifier
            .fillMaxWidth()
            .background(BaySurface, RoundedCornerShape(4.dp))
            .clickable(onClick = onClick)
            .padding(16.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                text = credential.title,
                style = MaterialTheme.typography.titleMedium,
                color = Paper,
                fontFamily = FontFamily.Monospace,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f)
            )
            IconButton(onClick = {
                // Sharing exposes the plaintext password to another app, so it always requires
                // a fresh biometric confirmation — even if the row is already revealed on-screen.
                requestReveal(onSuccess = { decrypted ->
                    val text = buildString {
                        append("Title: ${credential.title}\n")
                        if (credential.username.isNotBlank()) append("Username: ${credential.username}\n")
                        append("Password: $decrypted\n")
                        if (credential.url.isNotBlank()) append("URL: ${credential.url}\n")
                    }
                    val shareIntent = Intent(Intent.ACTION_SEND).apply {
                        type = "text/plain"
                        putExtra(Intent.EXTRA_TEXT, text)
                    }
                    context.startActivity(Intent.createChooser(shareIntent, "Share credential"))
                })
            }) {
                Icon(Icons.Default.Share, contentDescription = "Share credential", tint = Paper.copy(alpha = 0.6f))
            }
            IconButton(onClick = onDeleteRequest) {
                Icon(Icons.Default.Delete, contentDescription = "Delete credential", tint = Paper.copy(alpha = 0.6f))
            }
        }
        if (credential.username.isNotBlank()) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = credential.username,
                    style = MaterialTheme.typography.bodyMedium,
                    color = Paper.copy(alpha = 0.7f),
                    modifier = Modifier.weight(1f)
                )
                IconButton(
                    onClick = {
                        clipboard.setText(AnnotatedString(credential.username))
                        Toast.makeText(context, "Username copied", Toast.LENGTH_SHORT).show()
                    },
                    modifier = Modifier.size(32.dp)
                ) {
                    Icon(
                        Icons.Default.ContentCopy,
                        contentDescription = "Copy username",
                        tint = Paper.copy(alpha = 0.6f),
                        modifier = Modifier.size(16.dp)
                    )
                }
            }
        }
        if (credential.url.isNotBlank()) {
            Text(
                text = credential.url,
                style = MaterialTheme.typography.labelSmall,
                color = Paper.copy(alpha = 0.5f),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }
        Spacer(Modifier.height(8.dp))
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                text = revealedPassword ?: "••••••••",
                style = MaterialTheme.typography.bodyMedium,
                color = if (revealedPassword != null) AmberTab else Paper.copy(alpha = 0.5f),
                fontFamily = FontFamily.Monospace,
                modifier = Modifier.weight(1f)
            )
            IconButton(onClick = {
                // Copying exposes the plaintext password to the clipboard, so it always requires
                // a fresh biometric confirmation — even if the row is already revealed on-screen.
                requestReveal(onSuccess = { decrypted ->
                    clipboard.setText(AnnotatedString(decrypted))
                    Toast.makeText(context, "Password copied", Toast.LENGTH_SHORT).show()
                })
            }) {
                Icon(
                    Icons.Default.ContentCopy,
                    contentDescription = "Copy password",
                    tint = Paper.copy(alpha = 0.6f)
                )
            }
            IconButton(onClick = {
                if (revealedPassword != null) {
                    revealedPassword = null
                } else {
                    requestReveal(onSuccess = { revealedPassword = it })
                }
            }) {
                Icon(
                    imageVector = when {
                        revealedPassword != null -> Icons.Default.VisibilityOff
                        else -> Icons.Default.Fingerprint
                    },
                    contentDescription = if (revealedPassword != null) "Hide password" else "Reveal password",
                    tint = Paper.copy(alpha = 0.6f)
                )
            }
        }
    }
}
