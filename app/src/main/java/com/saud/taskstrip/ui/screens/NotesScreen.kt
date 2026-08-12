package com.saud.taskstrip.ui.screens

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
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.CallSplit
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.FlightTakeoff
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextFieldDefaults
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
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.saud.taskstrip.NoteViewModel
import com.saud.taskstrip.TaskViewModel
import com.saud.taskstrip.data.NoteEntity
import com.saud.taskstrip.data.Priority
import com.saud.taskstrip.ui.components.formatTimestampShort
import com.saud.taskstrip.ui.theme.AmberTab
import com.saud.taskstrip.ui.theme.BayBackground
import com.saud.taskstrip.ui.theme.BaySurface
import com.saud.taskstrip.ui.theme.Paper

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NotesScreen(
    noteViewModel: NoteViewModel,
    taskViewModel: TaskViewModel,
    onBack: () -> Unit
) {
    val notes by noteViewModel.notes.collectAsStateWithLifecycle()
    var draft by rememberSaveable { mutableStateOf("") }

    Scaffold(
        containerColor = BayBackground,
        topBar = {
            TopAppBar(
                title = { Text("QUICK NOTES", style = MaterialTheme.typography.titleLarge, color = Paper) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back", tint = Paper)
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = BayBackground)
            )
        }
    ) { padding ->
        Column(Modifier.padding(padding).fillMaxSize()) {
            Row(
                verticalAlignment = Alignment.Bottom,
                modifier = Modifier.fillMaxWidth().padding(12.dp)
            ) {
                fun submit() {
                    if (draft.isNotBlank()) {
                        noteViewModel.add(draft)
                        draft = ""
                    }
                }
                // Multi-line on purpose: jotting down meeting notes as several lines (one per
                // point) is what makes "split into strips" below useful — Enter inserts a new
                // line here, the send icon is the only way to submit.
                OutlinedTextField(
                    value = draft,
                    onValueChange = { draft = it },
                    placeholder = { Text("Jot a thought… (one point per line for meeting notes)", color = Paper.copy(alpha = 0.4f)) },
                    maxLines = 6,
                    textStyle = MaterialTheme.typography.bodyLarge.copy(fontFamily = FontFamily.Monospace, color = Paper),
                    colors = TextFieldDefaults.colors(
                        focusedTextColor = Paper,
                        unfocusedTextColor = Paper,
                        focusedContainerColor = androidx.compose.ui.graphics.Color.Transparent,
                        unfocusedContainerColor = androidx.compose.ui.graphics.Color.Transparent
                    ),
                    modifier = Modifier.weight(1f)
                )
                IconButton(onClick = { submit() }) {
                    Icon(Icons.AutoMirrored.Filled.Send, contentDescription = "Add note", tint = AmberTab)
                }
            }

            if (notes.isEmpty()) {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Text(
                        text = "NO NOTES YET",
                        style = MaterialTheme.typography.titleMedium,
                        color = Paper.copy(alpha = 0.5f)
                    )
                }
            } else {
                LazyColumn(
                    modifier = Modifier.fillMaxSize(),
                    contentPadding = androidx.compose.foundation.layout.PaddingValues(12.dp)
                ) {
                    items(notes, key = { it.id }) { note ->
                        val lines = remember(note.text) { note.text.lines().map { it.trim() }.filter { it.isNotBlank() } }
                        NoteRow(
                            note = note,
                            canSplit = lines.size > 1,
                            onDelete = { noteViewModel.delete(note) },
                            onPromote = {
                                taskViewModel.addTask(
                                    note.text.lineSequence().firstOrNull()?.take(80) ?: note.text.take(80),
                                    "", note.text, Priority.NORMAL, null, 0,
                                    emptyList(), emptyList(), emptyList(), emptyList(), null
                                )
                                noteViewModel.delete(note)
                            },
                            onSplit = {
                                lines.forEach { line ->
                                    val cleaned = line
                                        .removePrefix("[ ]")
                                        .removePrefix("[x]")
                                        .removePrefix("[X]")
                                        .removePrefix("[✓]")
                                        .trim()
                                    taskViewModel.addTask(
                                        cleaned.ifBlank { line }.take(80),
                                        "", "", Priority.NORMAL, null, 0,
                                        emptyList(), emptyList(), emptyList(), emptyList(), null
                                    )
                                }
                                noteViewModel.delete(note)
                            }
                        )
                        Spacer(Modifier.height(8.dp))
                    }
                }
            }
        }
    }
}

@Composable
private fun NoteRow(
    note: NoteEntity,
    canSplit: Boolean,
    onDelete: () -> Unit,
    onPromote: () -> Unit,
    onSplit: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(BaySurface, RoundedCornerShape(4.dp))
            .padding(16.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(Modifier.weight(1f)) {
            Text(
                text = note.text,
                style = MaterialTheme.typography.bodyMedium,
                color = Paper
            )
            Text(
                text = formatTimestampShort(note.createdAt),
                style = MaterialTheme.typography.labelSmall,
                color = Paper.copy(alpha = 0.5f)
            )
        }
        if (canSplit) {
            IconButton(onClick = onSplit) {
                Icon(Icons.AutoMirrored.Filled.CallSplit, contentDescription = "Split into strips", tint = AmberTab)
            }
        }
        IconButton(onClick = onPromote) {
            Icon(Icons.Default.FlightTakeoff, contentDescription = "Promote to strip", tint = AmberTab)
        }
        IconButton(onClick = onDelete) {
            Icon(Icons.Default.Delete, contentDescription = "Delete note", tint = Paper.copy(alpha = 0.6f))
        }
    }
}
