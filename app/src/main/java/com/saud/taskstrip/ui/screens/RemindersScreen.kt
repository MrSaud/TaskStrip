package com.saud.taskstrip.ui.screens

import android.app.Activity
import android.content.ActivityNotFoundException
import android.speech.RecognizerIntent
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
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
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.VolumeUp
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Label
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.Repeat
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material.icons.filled.SwapVert
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CheckboxDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
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
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import kotlinx.coroutines.delay
import com.saud.taskstrip.ReminderViewModel
import com.saud.taskstrip.data.ReminderEntity
import com.saud.taskstrip.media.TextToSpeechHelper
import com.saud.taskstrip.ui.components.dueAtAsLocalInstant
import com.saud.taskstrip.ui.components.formatEtaFull
import com.saud.taskstrip.ui.theme.AmberTab
import com.saud.taskstrip.ui.theme.BayBackground
import com.saud.taskstrip.ui.theme.BaySurface
import com.saud.taskstrip.ui.theme.InkColor
import com.saud.taskstrip.ui.theme.Paper
import com.saud.taskstrip.ui.theme.PriorityUrgent

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RemindersScreen(
    viewModel: ReminderViewModel,
    onBack: () -> Unit,
    onAddClick: () -> Unit,
    onEditClick: (Long) -> Unit
) {
    val context = LocalContext.current
    val reminders by viewModel.reminders.collectAsStateWithLifecycle()
    var pendingDelete by remember { mutableStateOf<ReminderEntity?>(null) }
    var newReminderMenuExpanded by remember { mutableStateOf(false) }
    var searchActive by remember { mutableStateOf(false) }
    var searchQuery by remember { mutableStateOf("") }
    var sortDescending by remember { mutableStateOf(false) }
    var sortMenuExpanded by remember { mutableStateOf(false) }
    var tagFilter by remember { mutableStateOf<String?>(null) }
    var tagMenuExpanded by remember { mutableStateOf(false) }
    val searchFocusRequester = remember { FocusRequester() }

    LaunchedEffect(searchActive) {
        if (searchActive) searchFocusRequester.requestFocus()
    }

    // Tag -> emoji for the filter menu's labels — last reminder using a given tag wins if two
    // reminders sharing a tag name were given different emoji.
    val tagEmojis = remember(reminders) {
        reminders.filter { it.tag.isNotBlank() }.associate { it.tag to it.tagEmoji }
    }
    val availableTags = remember(tagEmojis) { tagEmojis.keys.sorted() }

    val visibleReminders = remember(reminders, searchQuery, sortDescending, tagFilter) {
        var filtered = if (searchQuery.isBlank()) {
            reminders
        } else {
            reminders.filter { it.text.contains(searchQuery, ignoreCase = true) }
        }
        tagFilter?.let { tag -> filtered = filtered.filter { it.tag == tag } }
        if (sortDescending) filtered.sortedByDescending { it.triggerAt } else filtered.sortedBy { it.triggerAt }
    }

    // Ticks the countdown labels every second while this screen is open, so the seconds digit
    // visibly animates rather than jumping in coarse steps.
    var nowMillis by remember { mutableStateOf(System.currentTimeMillis()) }
    LaunchedEffect(Unit) {
        while (true) {
            nowMillis = System.currentTimeMillis()
            delay(1_000)
        }
    }

    val voiceLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.StartActivityForResult()
    ) { result ->
        if (result.resultCode == Activity.RESULT_OK) {
            val spoken = result.data
                ?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)
                ?.firstOrNull()
            if (!spoken.isNullOrBlank()) {
                viewModel.setPendingText(spoken)
                onAddClick()
            }
        }
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
                            placeholder = { Text("Search reminders…") },
                            singleLine = true,
                            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                            keyboardActions = KeyboardActions(onSearch = {}),
                            colors = TextFieldDefaults.colors(
                                focusedContainerColor = Color.Transparent,
                                unfocusedContainerColor = Color.Transparent,
                                focusedIndicatorColor = Color.Transparent,
                                unfocusedIndicatorColor = Color.Transparent,
                                cursorColor = AmberTab,
                                focusedTextColor = Paper,
                                unfocusedTextColor = Paper
                            )
                        )
                    } else {
                        Text("REMINDERS", style = MaterialTheme.typography.titleLarge, color = Paper)
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
                        IconButton(onClick = { sortMenuExpanded = true }) {
                            Icon(
                                Icons.Default.SwapVert,
                                contentDescription = "Sort by date/time",
                                tint = if (sortDescending) AmberTab else Paper
                            )
                        }
                        DropdownMenu(expanded = sortMenuExpanded, onDismissRequest = { sortMenuExpanded = false }) {
                            DropdownMenuItem(
                                text = { Text("SOONEST FIRST") },
                                trailingIcon = {
                                    if (!sortDescending) Icon(Icons.Default.Check, contentDescription = null, tint = AmberTab)
                                },
                                onClick = {
                                    sortDescending = false
                                    sortMenuExpanded = false
                                }
                            )
                            DropdownMenuItem(
                                text = { Text("LATEST FIRST") },
                                trailingIcon = {
                                    if (sortDescending) Icon(Icons.Default.Check, contentDescription = null, tint = AmberTab)
                                },
                                onClick = {
                                    sortDescending = true
                                    sortMenuExpanded = false
                                }
                            )
                        }
                        if (availableTags.isNotEmpty()) {
                            IconButton(onClick = { tagMenuExpanded = true }) {
                                Icon(
                                    Icons.Default.Label,
                                    contentDescription = "Filter by tag",
                                    tint = if (tagFilter != null) AmberTab else Paper
                                )
                            }
                            DropdownMenu(expanded = tagMenuExpanded, onDismissRequest = { tagMenuExpanded = false }) {
                                DropdownMenuItem(
                                    text = { Text("ALL TAGS") },
                                    trailingIcon = {
                                        if (tagFilter == null) Icon(Icons.Default.Check, contentDescription = null, tint = AmberTab)
                                    },
                                    onClick = {
                                        tagFilter = null
                                        tagMenuExpanded = false
                                    }
                                )
                                availableTags.forEach { tag ->
                                    DropdownMenuItem(
                                        text = { Text("${tagEmojis[tag].orEmpty()} ${tag.uppercase()}".trim()) },
                                        trailingIcon = {
                                            if (tagFilter == tag) Icon(Icons.Default.Check, contentDescription = null, tint = AmberTab)
                                        },
                                        onClick = {
                                            tagFilter = tag
                                            tagMenuExpanded = false
                                        }
                                    )
                                }
                            }
                        }
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = BayBackground)
            )
        },
        floatingActionButton = {
            Box {
                ExtendedFloatingActionButton(
                    onClick = { newReminderMenuExpanded = true },
                    containerColor = AmberTab,
                    contentColor = InkColor,
                    icon = { Icon(Icons.Default.Add, contentDescription = null) },
                    text = { Text("NEW REMINDER", style = MaterialTheme.typography.bodyLarge) }
                )
                DropdownMenu(expanded = newReminderMenuExpanded, onDismissRequest = { newReminderMenuExpanded = false }) {
                    DropdownMenuItem(
                        text = { Text("CREATE") },
                        leadingIcon = { Icon(Icons.Default.Add, contentDescription = null) },
                        onClick = {
                            newReminderMenuExpanded = false
                            onAddClick()
                        }
                    )
                    DropdownMenuItem(
                        text = { Text("CREATE BY VOICE") },
                        leadingIcon = { Icon(Icons.Default.Mic, contentDescription = null) },
                        onClick = {
                            newReminderMenuExpanded = false
                            val intent = android.content.Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                                putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                                putExtra(RecognizerIntent.EXTRA_PROMPT, "Speak your reminder")
                            }
                            try {
                                voiceLauncher.launch(intent)
                            } catch (e: ActivityNotFoundException) {
                                Toast.makeText(context, "Voice input isn't available on this device", Toast.LENGTH_SHORT).show()
                            }
                        }
                    )
                }
            }
        }
    ) { padding ->
        if (reminders.isEmpty()) {
            Box(Modifier.padding(padding).fillMaxSize(), contentAlignment = Alignment.Center) {
                Text(
                    text = "NO REMINDERS SET",
                    style = MaterialTheme.typography.titleMedium,
                    color = Paper.copy(alpha = 0.5f)
                )
            }
        } else if (visibleReminders.isEmpty()) {
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
                contentPadding = PaddingValues(12.dp)
            ) {
                items(visibleReminders, key = { it.id }) { reminder ->
                    ReminderRow(
                        reminder = reminder,
                        nowMillis = nowMillis,
                        onClick = { onEditClick(reminder.id) },
                        onToggleDone = { viewModel.toggleDone(reminder) },
                        onDeleteRequest = { pendingDelete = reminder }
                    )
                    Spacer(Modifier.height(10.dp))
                }
            }
        }
    }

    pendingDelete?.let { reminder ->
        AlertDialog(
            onDismissRequest = { pendingDelete = null },
            title = { Text("DELETE REMINDER?", style = MaterialTheme.typography.titleMedium) },
            text = { Text("\"${reminder.text}\" will be permanently deleted. This can't be undone.") },
            confirmButton = {
                TextButton(onClick = {
                    viewModel.delete(reminder)
                    pendingDelete = null
                }) { Text("DELETE", color = PriorityUrgent) }
            },
            dismissButton = {
                TextButton(onClick = { pendingDelete = null }) { Text("CANCEL") }
            }
        )
    }
}

// "2d 5h 3m 12s remaining", dropping leading zero units so "3m 12s remaining" doesn't read as
// "0d 0h 3m 12s". Seconds are always shown so the label visibly ticks every second.
private fun formatRemaining(targetMillis: Long, nowMillis: Long): String {
    val diff = targetMillis - nowMillis
    if (diff <= 0) return "Overdue"
    val totalSeconds = diff / 1_000
    val days = totalSeconds / (24 * 60 * 60)
    val hours = (totalSeconds % (24 * 60 * 60)) / 3600
    val minutes = (totalSeconds % 3600) / 60
    val seconds = totalSeconds % 60
    val parts = buildList {
        if (days > 0) add("${days}d")
        if (days > 0 || hours > 0) add("${hours}h")
        if (days > 0 || hours > 0 || minutes > 0) add("${minutes}m")
        add("${seconds}s")
    }
    return parts.joinToString(" ") + " remaining"
}

// Offset so a reminder's id never collides with a strip's task id in TextToSpeechHelper's shared
// "who is currently speaking" state — both features reuse the same single TTS engine/tracker.
private const val REMINDER_SPEECH_ID_BASE = 500_000_000L

@Composable
private fun ReminderRow(
    reminder: ReminderEntity,
    nowMillis: Long,
    onClick: () -> Unit,
    onToggleDone: () -> Unit,
    onDeleteRequest: () -> Unit
) {
    val context = LocalContext.current
    val realTriggerAt = dueAtAsLocalInstant(reminder.triggerAt)
    val isOverdue = !reminder.isDone && realTriggerAt <= nowMillis
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .background(BaySurface, RoundedCornerShape(4.dp))
            .clickable(onClick = onClick)
            .padding(horizontal = 6.dp)
    ) {
        Checkbox(
            checked = reminder.isDone,
            onCheckedChange = { onToggleDone() },
            colors = CheckboxDefaults.colors(checkedColor = AmberTab, uncheckedColor = Paper.copy(alpha = 0.5f))
        )
        Column(Modifier.weight(1f).padding(vertical = 14.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = reminder.text,
                    style = MaterialTheme.typography.titleMedium,
                    color = Paper,
                    fontFamily = FontFamily.Monospace,
                    textDecoration = if (reminder.isDone) TextDecoration.LineThrough else null
                )
                if (reminder.repeatUnit != null) {
                    Spacer(Modifier.width(8.dp))
                    Icon(
                        Icons.Default.Repeat,
                        contentDescription = "Repeats every ${reminder.repeatAmount ?: 1} ${reminder.repeatUnit.lowercase()}",
                        tint = Paper.copy(alpha = 0.45f),
                        modifier = Modifier.height(14.dp)
                    )
                }
                val speakingId by TextToSpeechHelper.speakingTaskId
                val speechId = REMINDER_SPEECH_ID_BASE + reminder.id
                val isReadingThis = speakingId == speechId
                Spacer(Modifier.width(8.dp))
                Icon(
                    imageVector = if (isReadingThis) Icons.Default.Stop else Icons.AutoMirrored.Filled.VolumeUp,
                    contentDescription = if (isReadingThis) "Stop reading reminder" else "Read reminder aloud",
                    tint = if (isReadingThis) AmberTab else Paper.copy(alpha = 0.5f),
                    modifier = Modifier
                        .height(16.dp)
                        .clickable {
                            if (isReadingThis) {
                                TextToSpeechHelper.stop()
                            } else {
                                val speech = if (reminder.description.isNotBlank()) {
                                    "${reminder.text}. ${reminder.description}"
                                } else {
                                    reminder.text
                                }
                                TextToSpeechHelper.speak(context, speechId, speech)
                            }
                        }
                )
            }
            if (reminder.description.isNotBlank()) {
                Text(
                    text = reminder.description,
                    style = MaterialTheme.typography.bodyMedium,
                    color = Paper.copy(alpha = 0.6f),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
            Spacer(Modifier.height(4.dp))
            Text(
                text = formatEtaFull(reminder.triggerAt),
                style = MaterialTheme.typography.labelSmall,
                color = if (isOverdue) PriorityUrgent else Paper.copy(alpha = 0.5f)
            )
            if (!reminder.isDone) {
                Text(
                    text = formatRemaining(realTriggerAt, nowMillis),
                    style = MaterialTheme.typography.labelSmall,
                    color = if (isOverdue) PriorityUrgent else AmberTab.copy(alpha = 0.8f)
                )
            }
            if (reminder.tag.isNotBlank()) {
                Text(
                    text = reminder.tag.uppercase(),
                    style = MaterialTheme.typography.labelSmall,
                    color = AmberTab.copy(alpha = 0.7f)
                )
            }
        }
        if (reminder.tagEmoji.isNotBlank()) {
            Text(text = reminder.tagEmoji, fontSize = 28.sp)
            Spacer(Modifier.width(4.dp))
        }
        IconButton(onClick = onDeleteRequest) {
            Icon(Icons.Default.Delete, contentDescription = "Delete reminder", tint = Paper.copy(alpha = 0.6f))
        }
    }
}
