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
import androidx.compose.material.icons.filled.Add
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.saud.taskstrip.TaskViewModel
import com.saud.taskstrip.data.TaskContact
import com.saud.taskstrip.ui.theme.AmberTab
import com.saud.taskstrip.ui.theme.BayBackground
import com.saud.taskstrip.ui.theme.InkColor
import com.saud.taskstrip.ui.theme.Paper
import com.saud.taskstrip.ui.theme.tabColor
import com.saud.taskstrip.voice.VoiceDraft

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ShareTargetScreen(
    content: VoiceDraft,
    viewModel: TaskViewModel,
    onCreateNew: (VoiceDraft) -> Unit,
    onDone: () -> Unit
) {
    val tasks by viewModel.tasks.collectAsStateWithLifecycle()
    val active = remember(tasks) { tasks.filter { !it.isDone } }
    var query by remember { mutableStateOf("") }
    val filtered = remember(active, query) {
        if (query.isBlank()) active else active.filter { it.title.contains(query, ignoreCase = true) }
    }

    Scaffold(
        containerColor = BayBackground,
        topBar = {
            TopAppBar(
                title = { Text("SHARE TO STRIP", style = MaterialTheme.typography.titleLarge, color = Paper) },
                navigationIcon = {
                    IconButton(onClick = onDone) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Cancel", tint = Paper)
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = BayBackground)
            )
        }
    ) { padding ->
        Column(
            Modifier
                .padding(padding)
                .padding(horizontal = 20.dp)
                .fillMaxSize()
        ) {
            Spacer(Modifier.height(12.dp))
            Surface(color = Paper, shape = RoundedCornerShape(4.dp), modifier = Modifier.fillMaxWidth()) {
                Column(Modifier.padding(14.dp)) {
                    Text(
                        text = content.title.uppercase(),
                        style = MaterialTheme.typography.titleMedium,
                        color = InkColor,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis
                    )
                    if (content.notes.isNotBlank()) {
                        Spacer(Modifier.height(4.dp))
                        Text(
                            text = content.notes,
                            style = MaterialTheme.typography.bodyMedium,
                            color = InkColor.copy(alpha = 0.7f),
                            maxLines = 4,
                            overflow = TextOverflow.Ellipsis
                        )
                    }
                }
            }

            Spacer(Modifier.height(16.dp))
            Surface(
                onClick = { onCreateNew(content) },
                color = AmberTab,
                shape = RoundedCornerShape(4.dp),
                modifier = Modifier.fillMaxWidth().height(52.dp)
            ) {
                Row(Modifier.fillMaxSize(), horizontalArrangement = androidx.compose.foundation.layout.Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Default.Add, contentDescription = null, tint = InkColor)
                    Spacer(Modifier.width(8.dp))
                    Text(
                        "CREATE NEW STRIP",
                        style = MaterialTheme.typography.titleMedium,
                        color = InkColor
                    )
                }
            }

            if (active.isNotEmpty()) {
                Spacer(Modifier.height(24.dp))
                Text(
                    "OR ADD TO AN EXISTING STRIP",
                    style = MaterialTheme.typography.labelSmall,
                    color = Paper.copy(alpha = 0.7f)
                )
                Spacer(Modifier.height(8.dp))
                OutlinedTextField(
                    value = query,
                    onValueChange = { query = it },
                    placeholder = { Text("SEARCH STRIPS") },
                    singleLine = true,
                    colors = TextFieldDefaults.colors(
                        focusedTextColor = Paper,
                        unfocusedTextColor = Paper,
                        focusedContainerColor = Color.Transparent,
                        unfocusedContainerColor = Color.Transparent
                    ),
                    modifier = Modifier.fillMaxWidth()
                )
                Spacer(Modifier.height(8.dp))
                LazyColumn(Modifier.weight(1f)) {
                    items(filtered, key = { it.id }) { task ->
                        Surface(
                            onClick = {
                                if (content.contactEmail != null || content.contactPhone != null) {
                                    val contact = TaskContact(
                                        name = content.title,
                                        email = content.contactEmail.orEmpty(),
                                        phone = content.contactPhone.orEmpty()
                                    )
                                    viewModel.addContactToTask(task, contact)
                                } else {
                                    val separator = if (task.notes.isBlank()) "" else "\n\n"
                                    val addition = content.notes.ifBlank { content.title }
                                    viewModel.updateTask(task.copy(notes = task.notes + separator + addition))
                                }
                                onDone()
                            },
                            color = Paper,
                            shape = RoundedCornerShape(4.dp),
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(vertical = 4.dp)
                        ) {
                            Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                                Box(
                                    Modifier
                                        .width(6.dp)
                                        .height(24.dp)
                                        .clip(RoundedCornerShape(2.dp))
                                        .background(task.priority.tabColor())
                                )
                                Spacer(Modifier.width(10.dp))
                                Text(
                                    text = task.title.uppercase(),
                                    style = MaterialTheme.typography.bodyLarge,
                                    color = InkColor,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis,
                                    modifier = Modifier.weight(1f)
                                )
                            }
                        }
                    }
                }
            } else {
                Spacer(Modifier.height(20.dp))
            }
        }
    }
}
