package com.saud.taskstrip.ui.screens

import android.os.Build
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
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Sync
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
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
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.saud.taskstrip.data.AppDatabase
import com.saud.taskstrip.data.SyncNoteEntity
import com.saud.taskstrip.sync.SyncNoteSync
import com.saud.taskstrip.sync.toRecord
import com.saud.taskstrip.ui.theme.AmberTab
import com.saud.taskstrip.ui.theme.BayBackground
import com.saud.taskstrip.ui.theme.BaySurface
import com.saud.taskstrip.ui.theme.Paper
import com.saud.taskstrip.ui.theme.PriorityUrgent
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** The text list, and the text.
 *
 * Syncs when the screen opens, when it leaves, and whenever asked — the same three moments as the
 * Mac, so neither device is ever the only one that bothered. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SyncNotesScreen(onBack: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val dao = remember { AppDatabase.getInstance(context).syncNoteDao() }
    val clipboard = LocalClipboardManager.current

    /** Copying is most of why a text is worth syncing at all — it arrives on this device to be
     * pasted somewhere else on it. Android 13 and up shows its own confirmation for a copy, so
     * a toast there would be the second thing to say so. */
    fun copyToClipboard(text: String) {
        clipboard.setText(AnnotatedString(text))
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            Toast.makeText(context, "Copied", Toast.LENGTH_SHORT).show()
        }
    }

    var notes by remember { mutableStateOf<List<SyncNoteEntity>>(emptyList()) }
    var editing by remember { mutableStateOf<SyncNoteEntity?>(null) }
    var deleting by remember { mutableStateOf<SyncNoteEntity?>(null) }
    var isSyncing by remember { mutableStateOf(false) }
    var status by remember { mutableStateOf<String?>(null) }

    suspend fun reload() {
        notes = withContext(Dispatchers.IO) {
            dao.getAllOnce().filter { !it.isDeleted }.sortedByDescending { it.updatedAt }
        }
    }

    /** `quietly` is for the syncs nobody asked for — arriving and leaving. Those still report into
     * the status line, but they must not feel like a failure the user caused. */
    suspend fun sync(quietly: Boolean) {
        if (isSyncing) return
        isSyncing = true
        val outcome = SyncNoteSync.run(context)
        isSyncing = false
        status = if (quietly && outcome.failure != null) "Not synced yet." else outcome.summary
        reload()
    }

    LaunchedEffect(Unit) {
        reload()
        sync(quietly = true)
    }

    Scaffold(
        containerColor = BayBackground,
        topBar = {
            TopAppBar(
                title = { Text("SYNC NOTES", style = MaterialTheme.typography.titleLarge, color = Paper) },
                navigationIcon = {
                    IconButton(onClick = {
                        scope.launch {
                            sync(quietly = true)
                            onBack()
                        }
                    }) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back", tint = Paper)
                    }
                },
                actions = {
                    if (isSyncing) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(20.dp).padding(end = 8.dp),
                            color = AmberTab,
                            strokeWidth = 2.dp
                        )
                    } else {
                        IconButton(onClick = { scope.launch { sync(quietly = false) } }) {
                            Icon(Icons.Default.Sync, contentDescription = "Sync now", tint = Paper)
                        }
                    }
                    IconButton(onClick = { editing = SyncNoteEntity() }) {
                        Icon(Icons.Default.Add, contentDescription = "New synced note", tint = AmberTab)
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = BayBackground)
            )
        }
    ) { padding ->
        Column(Modifier.padding(padding).fillMaxSize()) {
            status?.let {
                Text(
                    text = it,
                    style = MaterialTheme.typography.labelSmall,
                    color = Paper.copy(alpha = 0.6f),
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp)
                )
            }

            if (notes.isEmpty()) {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Text(
                            "NOTHING SYNCED YET",
                            style = MaterialTheme.typography.titleMedium,
                            color = Paper.copy(alpha = 0.5f)
                        )
                        Text(
                            "Write something here and it turns up on the Mac.",
                            style = MaterialTheme.typography.bodyMedium,
                            color = Paper.copy(alpha = 0.35f)
                        )
                    }
                }
            } else {
                LazyColumn(
                    contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    items(notes, key = { it.id }) { note ->
                        Row(
                            Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(6.dp))
                                .background(BaySurface)
                                .clickable { editing = note }
                                .padding(14.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Column(Modifier.weight(1f)) {
                                Text(
                                    text = note.toRecord().displayTitle,
                                    style = MaterialTheme.typography.bodyLarge,
                                    color = Paper,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis
                                )
                                Text(
                                    text = SimpleDateFormat("dd MMM yyyy, HH:mm", Locale.US)
                                        .format(Date(note.updatedAt)),
                                    style = MaterialTheme.typography.labelSmall,
                                    color = Paper.copy(alpha = 0.5f)
                                )
                            }
                            Spacer(Modifier.width(8.dp))
                            IconButton(
                                onClick = { copyToClipboard(note.text) },
                                enabled = note.text.isNotEmpty()
                            ) {
                                Icon(
                                    Icons.Default.ContentCopy,
                                    contentDescription = "Copy ${note.toRecord().displayTitle}",
                                    tint = Paper.copy(alpha = if (note.text.isEmpty()) 0.25f else 0.6f)
                                )
                            }
                            IconButton(onClick = { deleting = note }) {
                                Icon(
                                    Icons.Default.Delete,
                                    contentDescription = "Delete ${note.toRecord().displayTitle}",
                                    tint = Paper.copy(alpha = 0.6f)
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    editing?.let { note ->
        SyncNoteEditorDialog(
            note = note,
            onCopy = ::copyToClipboard,
            onDismiss = { editing = null },
            onSave = { text ->
                editing = null
                scope.launch {
                    withContext(Dispatchers.IO) {
                        dao.upsert(
                            note.copy(
                                text = text,
                                updatedAt = System.currentTimeMillis(),
                                isDeleted = false
                            )
                        )
                    }
                    reload()
                    sync(quietly = true)
                }
            }
        )
    }

    deleting?.let { note ->
        AlertDialog(
            onDismissRequest = { deleting = null },
            title = { Text("DELETE THIS NOTE?", style = MaterialTheme.typography.titleMedium) },
            text = { Text("It goes from this phone and from the Mac on the next sync.") },
            confirmButton = {
                TextButton(onClick = {
                    deleting = null
                    scope.launch {
                        // A tombstone, not a removal: the row has to survive long enough to tell
                        // the Mac the note is gone, or the next sync brings it straight back.
                        withContext(Dispatchers.IO) {
                            dao.upsert(
                                note.copy(
                                    text = "",
                                    isDeleted = true,
                                    updatedAt = System.currentTimeMillis()
                                )
                            )
                        }
                        reload()
                        sync(quietly = true)
                    }
                }) { Text("DELETE", color = PriorityUrgent) }
            },
            dismissButton = { TextButton(onClick = { deleting = null }) { Text("CANCEL") } }
        )
    }
}

/** One text and nothing else.
 *
 * There was a title field above this and it earned its keep nowhere: the list names a note by its
 * first line whether or not a title was typed, so the field was a second place to write the same
 * thing and a decision to make before writing anything at all. */
@Composable
private fun SyncNoteEditorDialog(
    note: SyncNoteEntity,
    onCopy: (String) -> Unit,
    onDismiss: () -> Unit,
    onSave: (String) -> Unit
) {
    var text by remember(note.id) { mutableStateOf(note.text) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    "SYNCED NOTE",
                    style = MaterialTheme.typography.titleMedium,
                    modifier = Modifier.weight(1f)
                )
                // Copies the draft rather than what was last saved, so what lands on the clipboard
                // is what is on the screen.
                IconButton(onClick = { onCopy(text) }, enabled = text.isNotEmpty()) {
                    Icon(Icons.Default.ContentCopy, contentDescription = "Copy note text")
                }
            }
        },
        text = {
            OutlinedTextField(
                value = text,
                onValueChange = { text = it },
                label = { Text("Text") },
                minLines = 6,
                modifier = Modifier.fillMaxWidth()
            )
        },
        confirmButton = { TextButton(onClick = { onSave(text) }) { Text("SAVE") } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("CANCEL") } }
    )
}
