package com.saud.taskstrip.ui.screens

import android.widget.Toast
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.ContentPaste
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.DeleteSweep
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.PushPin
import androidx.compose.material.icons.filled.Sync
import androidx.compose.material.icons.filled.SyncDisabled
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExtendedFloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LocalTextStyle
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.saud.taskstrip.ClipboardViewModel
import com.saud.taskstrip.data.ClipboardEntity
import com.saud.taskstrip.ui.theme.AmberTab
import com.saud.taskstrip.ui.theme.BayBackground
import com.saud.taskstrip.ui.theme.BaySurface
import com.saud.taskstrip.ui.theme.Paper
import com.saud.taskstrip.ui.theme.PriorityUrgent

// Snippets parked for reuse. Everything here stays on the device — the sync toggle on each row
// only records intent for the desktop transport that comes later, it doesn't send anything yet.
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ClipboardScreen(
    viewModel: ClipboardViewModel,
    onBack: () -> Unit
) {
    val context = LocalContext.current
    val items by viewModel.items.collectAsStateWithLifecycle()

    var editTarget by remember { mutableStateOf<ClipboardEntity?>(null) }
    var pendingDelete by remember { mutableStateOf<ClipboardEntity?>(null) }
    var confirmClear by remember { mutableStateOf(false) }

    Scaffold(
        modifier = Modifier.imePadding(),
        containerColor = BayBackground,
        topBar = {
            TopAppBar(
                title = { Text("CLIPBOARD", style = MaterialTheme.typography.titleLarge, color = Paper) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back", tint = Paper)
                    }
                },
                actions = {
                    if (items.any { !it.isPinned }) {
                        IconButton(onClick = { confirmClear = true }) {
                            Icon(Icons.Default.DeleteSweep, contentDescription = "Clear unpinned", tint = Paper)
                        }
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = BayBackground)
            )
        },
        floatingActionButton = {
            ExtendedFloatingActionButton(
                onClick = {
                    if (!viewModel.pasteFromSystemClipboard()) {
                        Toast.makeText(context, "Nothing text-like on the clipboard", Toast.LENGTH_SHORT).show()
                    }
                },
                containerColor = AmberTab
            ) {
                Icon(Icons.Default.ContentPaste, contentDescription = null)
                Spacer(Modifier.width(8.dp))
                Text("PASTE")
            }
        }
    ) { padding ->
        Column(Modifier.padding(padding).fillMaxSize()) {
            if (items.isEmpty()) {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Text(
                            text = "NOTHING SAVED YET",
                            style = MaterialTheme.typography.titleMedium,
                            color = Paper.copy(alpha = 0.5f)
                        )
                        Spacer(Modifier.height(8.dp))
                        Text(
                            text = "Copy something, then tap PASTE — or share text\ninto Task Strips from any app.",
                            style = MaterialTheme.typography.bodySmall,
                            color = Paper.copy(alpha = 0.4f)
                        )
                    }
                }
            } else {
                LazyColumn(
                    modifier = Modifier.fillMaxSize(),
                    contentPadding = androidx.compose.foundation.layout.PaddingValues(12.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    items(items, key = { it.id }) { item ->
                        ClipboardRow(
                            item = item,
                            onCopy = {
                                viewModel.copyToSystemClipboard(item)
                                Toast.makeText(context, "Copied", Toast.LENGTH_SHORT).show()
                            },
                            onEdit = { editTarget = item },
                            onTogglePin = { viewModel.togglePinned(item) },
                            onToggleSync = { viewModel.toggleSyncable(item) },
                            onDelete = { pendingDelete = item }
                        )
                    }
                }
            }
        }
    }

    editTarget?.let { item ->
        ClipboardEditDialog(
            item = item,
            onDismiss = { editTarget = null },
            onSave = { text, label ->
                viewModel.setText(item, text)
                viewModel.setLabel(item, label)
                editTarget = null
            }
        )
    }

    pendingDelete?.let { item ->
        AlertDialog(
            onDismissRequest = { pendingDelete = null },
            title = { Text("DELETE SNIPPET?", style = MaterialTheme.typography.titleMedium) },
            text = { Text("This removes it from the clipboard list. Anything already pasted elsewhere is unaffected.") },
            confirmButton = {
                TextButton(onClick = {
                    viewModel.delete(item)
                    pendingDelete = null
                }) { Text("DELETE", color = PriorityUrgent) }
            },
            dismissButton = { TextButton(onClick = { pendingDelete = null }) { Text("CANCEL") } }
        )
    }

    if (confirmClear) {
        AlertDialog(
            onDismissRequest = { confirmClear = false },
            title = { Text("CLEAR UNPINNED?", style = MaterialTheme.typography.titleMedium) },
            text = { Text("Every snippet except the pinned ones will be deleted.") },
            confirmButton = {
                TextButton(onClick = {
                    viewModel.clearUnpinned()
                    confirmClear = false
                }) { Text("CLEAR", color = PriorityUrgent) }
            },
            dismissButton = { TextButton(onClick = { confirmClear = false }) { Text("CANCEL") } }
        )
    }
}

@Composable
private fun ClipboardRow(
    item: ClipboardEntity,
    onCopy: () -> Unit,
    onEdit: () -> Unit,
    onTogglePin: () -> Unit,
    onToggleSync: () -> Unit,
    onDelete: () -> Unit
) {
    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(6.dp))
            .background(BaySurface)
            // Tapping the body copies: the thing you came here to do, without hunting for a button.
            .clickable(onClick = onCopy)
            .padding(12.dp)
    ) {
        if (item.label.isNotBlank()) {
            Text(
                text = item.label.uppercase(),
                style = MaterialTheme.typography.labelSmall,
                color = AmberTab
            )
            Spacer(Modifier.height(4.dp))
        }
        Text(
            text = item.text,
            style = MaterialTheme.typography.bodyMedium.copy(fontFamily = FontFamily.Monospace),
            color = Paper.copy(alpha = 0.85f),
            maxLines = 4,
            overflow = TextOverflow.Ellipsis
        )
        Spacer(Modifier.height(6.dp))
        Row(verticalAlignment = Alignment.CenterVertically) {
            if (!item.isSyncable) {
                Text(
                    text = "LOCAL ONLY",
                    style = MaterialTheme.typography.labelSmall,
                    color = Paper.copy(alpha = 0.45f)
                )
            }
            Spacer(Modifier.weight(1f))
            IconButton(onClick = onTogglePin) {
                Icon(
                    Icons.Default.PushPin,
                    contentDescription = if (item.isPinned) "Unpin" else "Pin",
                    tint = if (item.isPinned) AmberTab else Paper.copy(alpha = 0.5f)
                )
            }
            IconButton(onClick = onToggleSync) {
                Icon(
                    imageVector = if (item.isSyncable) Icons.Default.Sync else Icons.Default.SyncDisabled,
                    contentDescription = if (item.isSyncable) "Make local only" else "Allow syncing",
                    tint = if (item.isSyncable) Paper.copy(alpha = 0.5f) else PriorityUrgent
                )
            }
            IconButton(onClick = onEdit) {
                Icon(Icons.Default.Edit, contentDescription = "Edit", tint = Paper.copy(alpha = 0.5f))
            }
            IconButton(onClick = onCopy) {
                Icon(Icons.Default.ContentCopy, contentDescription = "Copy", tint = AmberTab)
            }
            IconButton(onClick = onDelete) {
                Icon(Icons.Default.Delete, contentDescription = "Delete", tint = Paper.copy(alpha = 0.5f))
            }
        }
    }
}

@Composable
private fun ClipboardEditDialog(
    item: ClipboardEntity,
    onDismiss: () -> Unit,
    onSave: (String, String) -> Unit
) {
    var text by rememberSaveable(item.id) { mutableStateOf(item.text) }
    var label by rememberSaveable(item.id) { mutableStateOf(item.label) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("EDIT SNIPPET", style = MaterialTheme.typography.titleMedium) },
        text = {
            Column {
                OutlinedTextField(
                    value = label,
                    onValueChange = { label = it },
                    label = { Text("LABEL (optional)") },
                    singleLine = true,
                    textStyle = LocalTextStyle.current.copy(fontFamily = FontFamily.Monospace),
                    modifier = Modifier.fillMaxWidth()
                )
                Spacer(Modifier.height(10.dp))
                OutlinedTextField(
                    value = text,
                    onValueChange = { text = it },
                    label = { Text("TEXT") },
                    textStyle = LocalTextStyle.current.copy(fontFamily = FontFamily.Monospace),
                    modifier = Modifier.fillMaxWidth().height(160.dp)
                )
            }
        },
        confirmButton = {
            TextButton(onClick = { onSave(text, label) }) { Text("SAVE", color = AmberTab) }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("CANCEL") } }
    )
}
