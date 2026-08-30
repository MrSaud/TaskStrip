package com.saud.taskstrip.ui.screens

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.speech.RecognizerIntent
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.detectDragGesturesAfterLongPress
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Alarm
import androidx.compose.material.icons.filled.Archive
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.Sync
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.CloudUpload
import androidx.compose.material.icons.filled.DateRange
import androidx.compose.material.icons.filled.Draw
import androidx.compose.material.icons.filled.FilterList
import androidx.compose.material.icons.filled.FlightTakeoff
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material.icons.filled.Insights
import androidx.compose.material.icons.filled.IosShare
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.NoteAdd
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.SwapVert
import androidx.compose.material.icons.filled.Today
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SmallFloatingActionButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.zIndex
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.saud.taskstrip.TaskViewModel
import com.saud.taskstrip.data.Priority
import com.saud.taskstrip.data.TaskActionLogEntry
import com.saud.taskstrip.data.TaskEntity
import com.saud.taskstrip.notifications.DigestPrefs
import com.saud.taskstrip.notifications.DigestScheduler
import com.saud.taskstrip.notifications.WeeklyDigestPrefs
import com.saud.taskstrip.notifications.WeeklyDigestScheduler
import com.saud.taskstrip.quotes.Quote
import com.saud.taskstrip.quotes.QuoteShareRenderer
import com.saud.taskstrip.ui.components.DateRange
import com.saud.taskstrip.ui.components.DateRangeFilterDialog
import com.saud.taskstrip.ui.components.FlightStripRow
import com.saud.taskstrip.ui.components.StripHeight
import com.saud.taskstrip.ui.components.formatBoardHeaderClock
import com.saud.taskstrip.ui.components.formatGregorianHeaderLine
import com.saud.taskstrip.ui.components.formatHijriHeaderLine
import com.saud.taskstrip.ui.components.isDueTodayOrOverdue
import com.saud.taskstrip.ui.theme.AmberTab
import com.saud.taskstrip.ui.theme.BayBackground
import com.saud.taskstrip.ui.theme.BaySurface
import com.saud.taskstrip.ui.theme.InkColor
import com.saud.taskstrip.ui.theme.Paper
import com.saud.taskstrip.ui.theme.tabColor
import com.saud.taskstrip.voice.VoiceCommandParser
import kotlinx.coroutines.delay
import kotlin.math.roundToInt

private enum class ProgressSort { ASCENDING, DESCENDING }

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HomeScreen(
    viewModel: TaskViewModel,
    onAddClick: () -> Unit,
    onTaskClick: (Long) -> Unit,
    onArchiveClick: () -> Unit,
    onSketchesClick: () -> Unit,
    onCredentialsClick: () -> Unit,
    onBackupClick: () -> Unit,
    onNotesClick: () -> Unit,
    onStandupClick: () -> Unit,
    onTagProgressClick: () -> Unit,
    onRemindersClick: () -> Unit,
    onNewReminderClick: () -> Unit,
    onNewReminderByVoice: (String) -> Unit,
    onStorageClick: () -> Unit,
    onSyncNotesClick: () -> Unit = {}
) {
    val tasks by viewModel.tasks.collectAsStateWithLifecycle()
    val quote by viewModel.quote.collectAsStateWithLifecycle()

    var nowMillis by remember { mutableStateOf(System.currentTimeMillis()) }
    LaunchedEffect(Unit) {
        while (true) {
            nowMillis = System.currentTimeMillis()
            delay(1000)
        }
    }

    var menuExpanded by remember { mutableStateOf(false) }
    var newStripMenuExpanded by remember { mutableStateOf(false) }
    var reminderMenuExpanded by remember { mutableStateOf(false) }
    var searchActive by remember { mutableStateOf(false) }
    var searchQuery by remember { mutableStateOf("") }
    var filterMenuExpanded by remember { mutableStateOf(false) }
    var selectedPriorities by remember { mutableStateOf(setOf<Priority>()) }
    var dateRange by remember { mutableStateOf(DateRange.EMPTY) }
    var showDateFilterDialog by remember { mutableStateOf(false) }
    var progressSort by remember { mutableStateOf<ProgressSort?>(null) }
    var sortMenuExpanded by remember { mutableStateOf(false) }
    var todayOnly by remember { mutableStateOf(false) }
    var selectedTag by remember { mutableStateOf<String?>(null) }
    // Manual drag order only makes sense as "the" order when nothing else is reshaping the list.
    val isFiltering = searchQuery.isNotBlank() || selectedPriorities.isNotEmpty() || dateRange.isSet ||
        progressSort != null || todayOnly || selectedTag != null

    val allTags = remember(tasks) {
        tasks.flatMap { it.tags }.distinctBy { it.lowercase() }.sortedBy { it.lowercase() }
    }
    // A tag can vanish from the board (its last task edited/deleted) while still selected —
    // drop the now-nonexistent filter instead of silently showing an empty board forever.
    LaunchedEffect(allTags) {
        if (selectedTag != null && selectedTag !in allTags) selectedTag = null
    }

    val visibleTasks = remember(tasks, searchQuery, selectedPriorities, dateRange, todayOnly, selectedTag) {
        tasks.filter { t ->
            (selectedPriorities.isEmpty() || t.priority in selectedPriorities) &&
                dateRange.contains(t.createdAt) &&
                (!todayOnly || t.isDone || isDueTodayOrOverdue(t.dueAt, t.isDone)) &&
                (selectedTag == null || t.tags.any { it.equals(selectedTag, ignoreCase = true) }) &&
                (searchQuery.isBlank() ||
                    t.title.contains(searchQuery, ignoreCase = true) ||
                    t.tags.any { tag -> tag.contains(searchQuery, ignoreCase = true) } ||
                    t.notes.contains(searchQuery, ignoreCase = true))
        }
    }
    fun applySort(list: List<TaskEntity>): List<TaskEntity> = when (progressSort) {
        null -> list
        ProgressSort.ASCENDING -> list.sortedBy { it.progress }
        ProgressSort.DESCENDING -> list.sortedByDescending { it.progress }
    }
    val active = remember(visibleTasks, progressSort) { applySort(visibleTasks.filter { !it.isDone }) }
    val completed = remember(visibleTasks, progressSort) { applySort(visibleTasks.filter { it.isDone }) }

    // orderedActive is only meaningful mid-drag (seeded fresh from `active` the instant a drag
    // starts). Outside of a drag we always render `active` directly and synchronously — never a
    // separately-tracked copy — so it can't go stale relative to `completed` for even one frame.
    // That staleness used to let the same task.id show up in both lists at once (e.g. right after
    // marking a task done or archiving it), which crashes LazyColumn with a duplicate-key error.
    var orderedActive by remember { mutableStateOf(active) }
    var draggingIndex by remember { mutableStateOf<Int?>(null) }
    var dragStartIndex by remember { mutableStateOf(0) }
    var dragOffsetY by remember { mutableFloatStateOf(0f) }
    val itemHeightPx = with(LocalDensity.current) { StripHeight.toPx() }
    val displayActive = if (draggingIndex != null) orderedActive else active
    // The drag gesture's pointerInput coroutine is keyed on task.id and so is launched once and
    // never restarts as the board reorders — a plain `active` read inside its onDragStart closure
    // would stay frozen to whatever the board looked like the moment that row's gesture detector
    // first launched. rememberUpdatedState keeps that read live across every recomposition, so a
    // long-press-release (even with zero movement) always reorders from the *current* board state
    // instead of silently committing a stale snapshot over other tasks' current field values.
    val currentActive = rememberUpdatedState(active)

    var pendingArchive by remember { mutableStateOf<TaskEntity?>(null) }

    val context = LocalContext.current
    var digestEnabled by remember { mutableStateOf(DigestPrefs.isEnabled(context)) }
    var weeklyDigestEnabled by remember { mutableStateOf(WeeklyDigestPrefs.isEnabled(context)) }
    var showSummaryDateDialog by remember { mutableStateOf(false) }
    val voiceLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.StartActivityForResult()
    ) { result ->
        if (result.resultCode == Activity.RESULT_OK) {
            val spoken = result.data
                ?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)
                ?.firstOrNull()
            if (!spoken.isNullOrBlank()) {
                viewModel.setPendingDraft(VoiceCommandParser.parse(spoken))
                onAddClick()
            }
        }
    }
    val reminderVoiceLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.StartActivityForResult()
    ) { result ->
        if (result.resultCode == Activity.RESULT_OK) {
            val spoken = result.data
                ?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)
                ?.firstOrNull()
            if (!spoken.isNullOrBlank()) {
                onNewReminderByVoice(spoken)
            }
        }
    }

    Box(Modifier.fillMaxSize()) {
    Scaffold(
        containerColor = BayBackground,
        topBar = {
            TopAppBar(
                title = {
                    if (searchActive) {
                        TextField(
                            value = searchQuery,
                            onValueChange = { searchQuery = it },
                            placeholder = { Text("SEARCH STRIPS", color = Paper.copy(alpha = 0.4f)) },
                            singleLine = true,
                            textStyle = MaterialTheme.typography.bodyLarge.copy(fontFamily = FontFamily.Monospace, color = Paper),
                            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                            keyboardActions = KeyboardActions(onSearch = {}),
                            colors = TextFieldDefaults.colors(
                                focusedContainerColor = Color.Transparent,
                                unfocusedContainerColor = Color.Transparent,
                                focusedIndicatorColor = Color.Transparent,
                                unfocusedIndicatorColor = Color.Transparent,
                                cursorColor = AmberTab
                            ),
                            modifier = Modifier.fillMaxWidth()
                        )
                    } else {
                        // The dates used to hang off this title and had a quarter of the screen
                        // to do it in — see BoardDateStrip, which now carries them at full width.
                        //
                        // titleLarge wrapped "THE BOARD" onto two lines: six action icons leave
                        // the title about 113dp and the name needs about 117dp at that size. The
                        // name no longer has to be the largest thing on the screen now that the
                        // date strip below carries its own weight.
                        Text(
                            text = "THE BOARD",
                            style = MaterialTheme.typography.titleMedium,
                            color = Paper,
                            maxLines = 1
                        )
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
                        IconButton(onClick = { todayOnly = !todayOnly }) {
                            Icon(
                                Icons.Default.Today,
                                contentDescription = if (todayOnly) "Showing today & overdue only" else "Show today & overdue only",
                                tint = if (todayOnly) AmberTab else Paper
                            )
                        }
                        IconButton(onClick = { filterMenuExpanded = true }) {
                            Icon(
                                Icons.Default.FilterList,
                                contentDescription = "Filter",
                                tint = if (selectedPriorities.isNotEmpty()) AmberTab else Paper
                            )
                        }
                        DropdownMenu(expanded = filterMenuExpanded, onDismissRequest = { filterMenuExpanded = false }) {
                            Priority.entries.forEach { p ->
                                DropdownMenuItem(
                                    text = { Text(p.label, color = p.tabColor()) },
                                    trailingIcon = {
                                        if (p in selectedPriorities) {
                                            Icon(Icons.Default.Check, contentDescription = null, tint = p.tabColor())
                                        }
                                    },
                                    onClick = {
                                        selectedPriorities = if (p in selectedPriorities) {
                                            selectedPriorities - p
                                        } else {
                                            selectedPriorities + p
                                        }
                                    }
                                )
                            }
                            if (selectedPriorities.isNotEmpty()) {
                                DropdownMenuItem(
                                    text = { Text("CLEAR FILTER") },
                                    onClick = {
                                        selectedPriorities = emptySet()
                                        filterMenuExpanded = false
                                    }
                                )
                            }
                        }
                        IconButton(onClick = { showDateFilterDialog = true }) {
                            Icon(
                                Icons.Default.DateRange,
                                contentDescription = dateRange.label() ?: "Filter by filed date",
                                tint = if (dateRange.isSet) AmberTab else Paper
                            )
                        }
                        IconButton(onClick = { sortMenuExpanded = true }) {
                            Icon(
                                Icons.Default.SwapVert,
                                contentDescription = "Sort by progress",
                                tint = if (progressSort != null) AmberTab else Paper
                            )
                        }
                        DropdownMenu(expanded = sortMenuExpanded, onDismissRequest = { sortMenuExpanded = false }) {
                            DropdownMenuItem(
                                text = { Text("BOARD ORDER (DRAG)") },
                                trailingIcon = {
                                    if (progressSort == null) Icon(Icons.Default.Check, contentDescription = null, tint = AmberTab)
                                },
                                onClick = {
                                    progressSort = null
                                    sortMenuExpanded = false
                                }
                            )
                            DropdownMenuItem(
                                text = { Text("PROGRESS: LOW TO HIGH") },
                                trailingIcon = {
                                    if (progressSort == ProgressSort.ASCENDING) {
                                        Icon(Icons.Default.Check, contentDescription = null, tint = AmberTab)
                                    }
                                },
                                onClick = {
                                    progressSort = ProgressSort.ASCENDING
                                    sortMenuExpanded = false
                                }
                            )
                            DropdownMenuItem(
                                text = { Text("PROGRESS: HIGH TO LOW") },
                                trailingIcon = {
                                    if (progressSort == ProgressSort.DESCENDING) {
                                        Icon(Icons.Default.Check, contentDescription = null, tint = AmberTab)
                                    }
                                },
                                onClick = {
                                    progressSort = ProgressSort.DESCENDING
                                    sortMenuExpanded = false
                                }
                            )
                        }
                        IconButton(onClick = { menuExpanded = true }) {
                            Icon(Icons.Default.MoreVert, contentDescription = "Menu", tint = Paper)
                        }
                        DropdownMenu(expanded = menuExpanded, onDismissRequest = { menuExpanded = false }) {
                            DropdownMenuItem(
                                text = { Text("ARCHIVED TASKS") },
                                leadingIcon = { Icon(Icons.Default.Archive, contentDescription = null) },
                                onClick = {
                                    menuExpanded = false
                                    onArchiveClick()
                                }
                            )
                            DropdownMenuItem(
                                text = { Text("CREDENTIALS") },
                                leadingIcon = { Icon(Icons.Default.Lock, contentDescription = null) },
                                onClick = {
                                    menuExpanded = false
                                    onCredentialsClick()
                                }
                            )
                            DropdownMenuItem(
                                text = { Text("REMINDERS") },
                                leadingIcon = { Icon(Icons.Default.Alarm, contentDescription = null) },
                                onClick = {
                                    menuExpanded = false
                                    onRemindersClick()
                                }
                            )
                            DropdownMenuItem(
                                text = { Text("STORAGE") },
                                leadingIcon = { Icon(Icons.Default.Folder, contentDescription = null) },
                                onClick = {
                                    menuExpanded = false
                                    onStorageClick()
                                }
                            )
                            DropdownMenuItem(
                                text = { Text("BACKUP & RESTORE") },
                                leadingIcon = { Icon(Icons.Default.CloudUpload, contentDescription = null) },
                                onClick = {
                                    menuExpanded = false
                                    onBackupClick()
                                }
                            )
                            DropdownMenuItem(
                                text = { Text("DAILY DIGEST") },
                                leadingIcon = { Icon(Icons.Default.Notifications, contentDescription = null) },
                                trailingIcon = {
                                    if (digestEnabled) {
                                        Icon(Icons.Default.Check, contentDescription = null, tint = AmberTab)
                                    }
                                },
                                onClick = {
                                    digestEnabled = !digestEnabled
                                    DigestPrefs.setEnabled(context, digestEnabled)
                                    if (digestEnabled) {
                                        DigestScheduler.scheduleNext(context)
                                    } else {
                                        DigestScheduler.cancel(context)
                                    }
                                }
                            )
                            DropdownMenuItem(
                                text = { Text("WEEKLY REVIEW") },
                                leadingIcon = { Icon(Icons.Default.Notifications, contentDescription = null) },
                                trailingIcon = {
                                    if (weeklyDigestEnabled) {
                                        Icon(Icons.Default.Check, contentDescription = null, tint = AmberTab)
                                    }
                                },
                                onClick = {
                                    weeklyDigestEnabled = !weeklyDigestEnabled
                                    WeeklyDigestPrefs.setEnabled(context, weeklyDigestEnabled)
                                    if (weeklyDigestEnabled) {
                                        WeeklyDigestScheduler.scheduleNext(context)
                                    } else {
                                        WeeklyDigestScheduler.cancel(context)
                                    }
                                }
                            )
                            DropdownMenuItem(
                                text = { Text("STANDUP SUMMARY") },
                                leadingIcon = { Icon(Icons.Default.Groups, contentDescription = null) },
                                onClick = {
                                    menuExpanded = false
                                    onStandupClick()
                                }
                            )
                            DropdownMenuItem(
                                text = { Text("TAG PROGRESS") },
                                leadingIcon = { Icon(Icons.Default.Insights, contentDescription = null) },
                                onClick = {
                                    menuExpanded = false
                                    onTagProgressClick()
                                }
                            )
                            DropdownMenuItem(
                                text = { Text("SHARE SUMMARY") },
                                leadingIcon = { Icon(Icons.Default.IosShare, contentDescription = null) },
                                onClick = {
                                    menuExpanded = false
                                    showSummaryDateDialog = true
                                }
                            )
                        }
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = BayBackground)
            )
        },
        floatingActionButton = {
            Row(verticalAlignment = Alignment.CenterVertically) {
                SmallFloatingActionButton(
                    onClick = onSketchesClick,
                    containerColor = BaySurface,
                    contentColor = Paper
                ) {
                    Icon(Icons.Default.Draw, contentDescription = "Sketch notes")
                }
                Spacer(Modifier.width(10.dp))
                Box {
                    SmallFloatingActionButton(
                        onClick = { reminderMenuExpanded = true },
                        containerColor = BaySurface,
                        contentColor = Paper
                    ) {
                        Icon(Icons.Default.Alarm, contentDescription = "Reminders")
                    }
                    DropdownMenu(expanded = reminderMenuExpanded, onDismissRequest = { reminderMenuExpanded = false }) {
                        DropdownMenuItem(
                            text = { Text("VIEW REMINDERS") },
                            leadingIcon = { Icon(Icons.Default.Alarm, contentDescription = null) },
                            onClick = {
                                reminderMenuExpanded = false
                                onRemindersClick()
                            }
                        )
                        DropdownMenuItem(
                            text = { Text("NEW REMINDER") },
                            leadingIcon = { Icon(Icons.Default.Add, contentDescription = null) },
                            onClick = {
                                reminderMenuExpanded = false
                                onNewReminderClick()
                            }
                        )
                        DropdownMenuItem(
                            text = { Text("NEW REMINDER BY VOICE") },
                            leadingIcon = { Icon(Icons.Default.Mic, contentDescription = null) },
                            onClick = {
                                reminderMenuExpanded = false
                                val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                                    putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                                    putExtra(RecognizerIntent.EXTRA_PROMPT, "Speak your reminder")
                                }
                                try {
                                    reminderVoiceLauncher.launch(intent)
                                } catch (e: ActivityNotFoundException) {
                                    Toast.makeText(context, "Voice input isn't available on this device", Toast.LENGTH_SHORT).show()
                                }
                            }
                        )
                    }
                }
                Spacer(Modifier.width(10.dp))
                SmallFloatingActionButton(
                    onClick = onSyncNotesClick,
                    containerColor = BaySurface,
                    contentColor = Paper
                ) {
                    Icon(Icons.Default.Sync, contentDescription = "Sync notes")
                }
                Spacer(Modifier.width(10.dp))
                Box {
                    SmallFloatingActionButton(
                        onClick = { newStripMenuExpanded = true },
                        containerColor = BaySurface,
                        contentColor = Paper
                    ) {
                        Icon(Icons.Default.Add, contentDescription = "New strip")
                    }
                    DropdownMenu(expanded = newStripMenuExpanded, onDismissRequest = { newStripMenuExpanded = false }) {
                        DropdownMenuItem(
                            text = { Text("CREATE") },
                            leadingIcon = { Icon(Icons.Default.Add, contentDescription = null) },
                            onClick = {
                                newStripMenuExpanded = false
                                onAddClick()
                            }
                        )
                        DropdownMenuItem(
                            text = { Text("CREATE BY VOICE") },
                            leadingIcon = { Icon(Icons.Default.Mic, contentDescription = null) },
                            onClick = {
                                newStripMenuExpanded = false
                                val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                                    putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                                    putExtra(
                                        RecognizerIntent.EXTRA_PROMPT,
                                        "\"Create a strip for ..., description is ...\""
                                    )
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
        }
    ) { padding ->
        Column(Modifier.padding(padding).fillMaxSize()) {
            BoardDateStrip(nowMillis)
            quote?.let { QuoteOfDayCard(it) }
            if (allTags.isNotEmpty()) {
                LazyRow(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp)
                ) {
                    items(allTags, key = { it }) { tag ->
                        val isSelected = selectedTag?.equals(tag, ignoreCase = true) == true
                        FilterChip(
                            selected = isSelected,
                            onClick = { selectedTag = if (isSelected) null else tag },
                            label = { Text(tag.uppercase()) },
                            colors = FilterChipDefaults.filterChipColors(
                                containerColor = BaySurface,
                                labelColor = Paper.copy(alpha = 0.8f),
                                selectedContainerColor = AmberTab,
                                selectedLabelColor = InkColor
                            )
                        )
                    }
                }
            }
            Box(Modifier.weight(1f)) {
                if (tasks.isEmpty()) {
                    EmptyBoard()
                } else if (visibleTasks.isEmpty()) {
                    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        Text(
                            text = "NO STRIPS MATCH",
                            style = MaterialTheme.typography.titleMedium,
                            color = Paper.copy(alpha = 0.5f)
                        )
                    }
                } else {
                    LazyColumn(
                        modifier = Modifier.fillMaxSize(),
                        // Floating buttons sit on top of this list rather than resizing it, so
                        // without extra bottom space the last strip ends up permanently hidden
                        // behind them — pad the scrollable area past their footprint instead.
                        contentPadding = PaddingValues(bottom = 96.dp)
                    ) {
                        itemsIndexed(displayActive, key = { _, item -> item.id }) { index, task ->
                    val isDragging = draggingIndex == index
                    // Residual sub-row offset: total drag distance minus however many full
                    // row-heights have already been applied by reordering the list, so the
                    // lifted strip keeps tracking the finger smoothly across multi-row jumps.
                    val visualOffset = if (isDragging) {
                        dragOffsetY - (index - dragStartIndex) * itemHeightPx
                    } else {
                        0f
                    }
                    FlightStripRow(
                        task = task,
                        completed = false,
                        onClick = { onTaskClick(task.id) },
                        onToggleDone = { viewModel.toggleDone(task) },
                        onQuickLog = { text ->
                            viewModel.updateTask(task.copy(actionLog = task.actionLog + TaskActionLogEntry(text, System.currentTimeMillis())))
                        },
                        onDelete = { viewModel.deleteTask(task) },
                        blockerTask = task.blockedByTaskId?.let { id -> tasks.find { it.id == id } },
                        modifier = Modifier
                            .graphicsLayer { translationY = visualOffset }
                            .zIndex(if (isDragging) 1f else 0f),
                        dragModifier = if (isFiltering) null else Modifier.pointerInput(task.id) {
                            detectDragGesturesAfterLongPress(
                                onDragStart = {
                                    // Seed fresh from the current source list right as the drag
                                    // starts, and resolve this row's *current* position in that
                                    // fresh snapshot — never trust a value captured when this
                                    // item was last composed, since this pointerInput is keyed on
                                    // task.id only and won't restart just because the row's
                                    // position shifted from something else changing the list.
                                    orderedActive = currentActive.value
                                    val startIndex = currentActive.value.indexOfFirst { it.id == task.id }
                                    if (startIndex >= 0) {
                                        dragStartIndex = startIndex
                                        draggingIndex = startIndex
                                        dragOffsetY = 0f
                                    }
                                },
                                onDragEnd = {
                                    if (draggingIndex != null) viewModel.reorder(orderedActive)
                                    draggingIndex = null
                                    dragOffsetY = 0f
                                },
                                onDragCancel = {
                                    draggingIndex = null
                                    dragOffsetY = 0f
                                },
                                onDrag = { change, dragAmount ->
                                    change.consume()
                                    dragOffsetY += dragAmount.y
                                    val current = draggingIndex ?: return@detectDragGesturesAfterLongPress
                                    // Recomputed from the fixed start each time (not incrementally),
                                    // so a single fast drag can jump straight across many rows.
                                    val target = (dragStartIndex + (dragOffsetY / itemHeightPx).roundToInt())
                                        .coerceIn(0, orderedActive.lastIndex)
                                    if (target != current) {
                                        orderedActive = orderedActive.toMutableList().apply {
                                            add(target, removeAt(current))
                                        }
                                        draggingIndex = target
                                    }
                                }
                            )
                        }
                    )
                }

                if (completed.isNotEmpty()) {
                    item(key = "completed_header") { CompletedHeader(completed.size) }
                    items(completed, key = { it.id }) { task ->
                        FlightStripRow(
                            task = task,
                            completed = true,
                            onClick = { onTaskClick(task.id) },
                            onToggleDone = { viewModel.toggleDone(task) },
                            onQuickLog = { text ->
                                viewModel.updateTask(task.copy(actionLog = task.actionLog + TaskActionLogEntry(text, System.currentTimeMillis())))
                            },
                            onDelete = { viewModel.deleteTask(task) },
                            trailingActions = {
                                IconButton(onClick = { pendingArchive = task }) {
                                    Icon(
                                        Icons.Default.Archive,
                                        contentDescription = "Archive",
                                        tint = Paper.copy(alpha = 0.5f)
                                    )
                                }
                            }
                        )
                    }
                }
            }
        }
    }
    }
    }

        SmallFloatingActionButton(
            onClick = onNotesClick,
            containerColor = BaySurface,
            contentColor = Paper,
            modifier = Modifier
                .align(Alignment.BottomStart)
                .navigationBarsPadding()
                .padding(16.dp)
        ) {
            Icon(Icons.Default.NoteAdd, contentDescription = "Quick notes")
        }
    }

    if (showDateFilterDialog) {
        DateRangeFilterDialog(
            onDismiss = { showDateFilterDialog = false },
            onConfirm = { range -> dateRange = range },
            onClear = { dateRange = DateRange.EMPTY }
        )
    }

    if (showSummaryDateDialog) {
        DateRangeFilterDialog(
            onDismiss = { showSummaryDateDialog = false },
            onConfirm = { range ->
                val completedInRange = tasks.filter { val at = it.completedAt; it.isDone && at != null && range.contains(at) }
                val periodLabel = range.label() ?: "ALL TIME"
                val summary = buildString {
                    appendLine("STRIP SUMMARY — $periodLabel")
                    appendLine()
                    if (completedInRange.isEmpty()) {
                        appendLine("Nothing completed in this period.")
                    } else {
                        appendLine("${completedInRange.size} completed:")
                        completedInRange.forEach { appendLine("- ${it.title}") }
                    }
                }
                val intent = Intent(Intent.ACTION_SEND).apply {
                    type = "text/plain"
                    putExtra(Intent.EXTRA_TEXT, summary)
                }
                context.startActivity(Intent.createChooser(intent, "Share summary"))
            },
            onClear = {}
        )
    }

    pendingArchive?.let { task ->
        AlertDialog(
            onDismissRequest = { pendingArchive = null },
            title = { Text("ARCHIVE STRIP?", style = MaterialTheme.typography.titleMedium) },
            text = { Text("\"${task.title}\" will move to the archive and leave the board. You can unarchive it later.") },
            confirmButton = {
                TextButton(onClick = {
                    viewModel.archiveTask(task)
                    pendingArchive = null
                }) { Text("ARCHIVE") }
            },
            dismissButton = {
                TextButton(onClick = { pendingArchive = null }) { Text("CANCEL") }
            }
        )
    }
}

/** The board's date header, on a full-width row of its own under the app bar.
 *
 * It used to hang off the app bar's title, which shares its row with six action icons and is left
 * with roughly a quarter of the screen — narrower than the dates themselves, so they wrapped and
 * were then cut off by the bar's fixed height. Nothing here is shortened to make it fit; it simply
 * has the width it always needed.
 *
 * The clock sits apart on the right because it is the one part that changes every second, and the
 * two calendar lines beside it do not.
 */
@Composable
private fun BoardDateStrip(nowMillis: Long) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(Modifier.weight(1f)) {
            Text(
                text = formatGregorianHeaderLine(nowMillis),
                style = MaterialTheme.typography.labelSmall,
                color = Paper.copy(alpha = 0.65f),
                maxLines = 1
            )
            Text(
                text = formatHijriHeaderLine(nowMillis),
                style = MaterialTheme.typography.labelSmall,
                color = Paper.copy(alpha = 0.45f),
                maxLines = 1
            )
        }
        Spacer(Modifier.width(12.dp))
        Text(
            text = formatBoardHeaderClock(nowMillis),
            style = MaterialTheme.typography.titleMedium,
            color = AmberTab,
            maxLines = 1
        )
    }
}

@Composable
private fun QuoteOfDayCard(quote: Quote, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp)
            .background(BaySurface, RoundedCornerShape(4.dp))
            .border(1.dp, Paper.copy(alpha = 0.15f), RoundedCornerShape(4.dp))
            .padding(start = 16.dp, top = 16.dp, bottom = 16.dp, end = 4.dp),
        verticalAlignment = Alignment.Top
    ) {
        Column(Modifier.weight(1f)) {
            Text(
                text = "QUOTE OF THE DAY",
                style = MaterialTheme.typography.labelSmall,
                color = AmberTab
            )
            Spacer(Modifier.height(6.dp))
            Text(
                text = "\"${quote.text}\"",
                style = MaterialTheme.typography.bodyMedium,
                color = Paper,
                fontFamily = FontFamily.Monospace
            )
            Spacer(Modifier.height(4.dp))
            Text(
                text = "— ${quote.author}",
                style = MaterialTheme.typography.labelSmall,
                color = Paper.copy(alpha = 0.6f)
            )
        }
        IconButton(onClick = { QuoteShareRenderer.shareToWhatsAppStatus(context, quote) }) {
            Icon(
                Icons.Default.Share,
                contentDescription = "Share quote to WhatsApp status",
                tint = Paper.copy(alpha = 0.6f)
            )
        }
    }
}

@Composable
private fun CompletedHeader(count: Int) {
    Text(
        text = "COMPLETED ($count)",
        style = MaterialTheme.typography.labelSmall,
        color = Paper.copy(alpha = 0.5f),
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 24.dp, vertical = 12.dp)
    )
}

@Composable
private fun EmptyBoard(modifier: Modifier = Modifier) {
    Box(modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Icon(
                Icons.Default.FlightTakeoff,
                contentDescription = null,
                tint = Paper.copy(alpha = 0.3f),
                modifier = Modifier.padding(bottom = 12.dp)
            )
            Text(
                text = "NO STRIPS ON THE BOARD",
                style = MaterialTheme.typography.titleMedium,
                color = Paper.copy(alpha = 0.5f),
                textAlign = TextAlign.Center
            )
            Text(
                text = "Tap NEW STRIP to file your first task",
                style = MaterialTheme.typography.bodyMedium,
                color = Paper.copy(alpha = 0.35f),
                textAlign = TextAlign.Center,
                modifier = Modifier.padding(top = 4.dp)
            )
        }
    }
}
