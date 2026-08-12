package com.saud.taskstrip.ui.screens

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.CalendarContract
import android.widget.Toast
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.relocation.BringIntoViewRequester
import androidx.compose.foundation.relocation.bringIntoViewRequester
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.AddTask
import androidx.compose.material.icons.filled.Block
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.HourglassTop
import androidx.compose.material.icons.filled.Checklist
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Draw
import androidx.compose.material.icons.filled.EditNote
import androidx.compose.material.icons.filled.Fullscreen
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CheckboxDefaults
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.InputChip
import androidx.compose.material3.LocalTextStyle
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TimePicker
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.material3.rememberTimePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.saud.taskstrip.TaskViewModel
import com.saud.taskstrip.data.Priority
import com.saud.taskstrip.data.TaskActionLogEntry
import com.saud.taskstrip.data.TaskContact
import com.saud.taskstrip.data.TaskEntity
import com.saud.taskstrip.media.ShareImageRenderer
import com.saud.taskstrip.media.SketchStorage
import com.saud.taskstrip.ui.components.AttachmentsSection
import com.saud.taskstrip.ui.components.ContactsSection
import com.saud.taskstrip.ui.components.dueAtAsLocalInstant
import com.saud.taskstrip.ui.components.formatEtaFull
import com.saud.taskstrip.ui.components.formatTimestampFull
import com.saud.taskstrip.ui.theme.AmberTab
import com.saud.taskstrip.ui.theme.BayBackground
import com.saud.taskstrip.ui.theme.InkColor
import com.saud.taskstrip.ui.theme.Paper
import com.saud.taskstrip.ui.theme.PriorityUrgent
import com.saud.taskstrip.ui.theme.tabColor
import java.time.Instant
import java.time.ZoneOffset
import kotlin.math.roundToInt

private enum class ReminderUnit(val label: String, val minutesPer: Int) {
    MINUTES("MIN", 1),
    HOURS("HR", 60),
    DAYS("DAY", 1440)
}

private fun minutesToAmountAndUnit(minutes: Int): Pair<Int, ReminderUnit> = when {
    minutes >= 1440 && minutes % 1440 == 0 -> (minutes / 1440) to ReminderUnit.DAYS
    minutes >= 60 && minutes % 60 == 0 -> (minutes / 60) to ReminderUnit.HOURS
    else -> minutes to ReminderUnit.MINUTES
}

private enum class RepeatOption(val label: String, val days: Int) {
    DAILY("DAILY", 1),
    WEEKLY("WEEKLY", 7),
    MONTHLY("MONTHLY", 30)
}

private fun daysToRepeatOption(days: Int): RepeatOption =
    RepeatOption.entries.firstOrNull { it.days == days } ?: RepeatOption.DAILY

// Captures every field the form lets the user edit — compared by structural equality against the
// state right after load to decide whether leaving needs a save/discard prompt.
private data class FormSnapshot(
    val title: String,
    val tags: List<String>,
    val notes: String,
    val priority: Priority,
    val dueAt: Long?,
    val progress: Float,
    val images: List<String>,
    val voiceNotes: List<String>,
    val documents: List<String>,
    val videos: List<String>,
    val contacts: List<TaskContact>,
    val blockedByTaskId: Long?,
    val linkedSketchId: String?,
    val actionLog: List<TaskActionLogEntry>,
    val waitingOnName: String,
    val waitingOnSince: Long?,
    val waitingOnFollowUpDays: Int?,
    val reminderEnabled: Boolean,
    val reminderAmount: String,
    val reminderUnit: ReminderUnit,
    val repeatEnabled: Boolean,
    val repeatOption: RepeatOption
)

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun AddEditTaskScreen(
    viewModel: TaskViewModel,
    taskId: Long,
    onDone: () -> Unit,
    onOpenSketch: (String) -> Unit = {}
) {
    val context = LocalContext.current
    val isEditing = taskId >= 0
    val allTasksForPicker by viewModel.tasks.collectAsStateWithLifecycle()

    // Saveable: a system dialog (permission prompt, photo picker, camera) can cause Android to
    // kill this process in the background, so in-progress form input must survive that, not just
    // configuration changes.
    var title by rememberSaveable { mutableStateOf("") }
    var tags by rememberSaveable { mutableStateOf<List<String>>(emptyList()) }
    var tagInput by rememberSaveable { mutableStateOf("") }
    var notes by rememberSaveable { mutableStateOf("") }
    var priority by rememberSaveable { mutableStateOf(Priority.NORMAL) }
    var dueAt by rememberSaveable { mutableStateOf<Long?>(null) }
    var progress by rememberSaveable { mutableStateOf(0f) }
    var images by rememberSaveable { mutableStateOf<List<String>>(emptyList()) }
    var voiceNotes by rememberSaveable { mutableStateOf<List<String>>(emptyList()) }
    var documents by rememberSaveable { mutableStateOf<List<String>>(emptyList()) }
    var videos by rememberSaveable { mutableStateOf<List<String>>(emptyList()) }
    var contacts by rememberSaveable { mutableStateOf<List<TaskContact>>(emptyList()) }
    var blockedByTaskId by rememberSaveable { mutableStateOf<Long?>(null) }
    var linkedSketchId by rememberSaveable { mutableStateOf<String?>(null) }
    var actionLog by rememberSaveable { mutableStateOf<List<TaskActionLogEntry>>(emptyList()) }
    var waitingOnName by rememberSaveable { mutableStateOf("") }
    var waitingOnSince by rememberSaveable { mutableStateOf<Long?>(null) }
    var waitingOnFollowUpDays by rememberSaveable { mutableStateOf<Int?>(null) }
    var loadedTask by remember { mutableStateOf<TaskEntity?>(null) }

    var reminderEnabled by rememberSaveable { mutableStateOf(false) }
    var reminderAmount by rememberSaveable { mutableStateOf("30") }
    var reminderUnit by rememberSaveable { mutableStateOf(ReminderUnit.MINUTES) }

    var repeatEnabled by rememberSaveable { mutableStateOf(false) }
    var repeatOption by rememberSaveable { mutableStateOf(RepeatOption.DAILY) }

    var showDatePicker by rememberSaveable { mutableStateOf(false) }
    var showTimePicker by rememberSaveable { mutableStateOf(false) }
    var showDeleteConfirm by rememberSaveable { mutableStateOf(false) }
    var showNotesEditor by rememberSaveable { mutableStateOf(false) }
    var pendingDateMillis by rememberSaveable { mutableStateOf<Long?>(null) }

    var initialSnapshot by remember { mutableStateOf<FormSnapshot?>(null) }
    var showExitConfirm by rememberSaveable { mutableStateOf(false) }

    fun currentSnapshot() = FormSnapshot(
        title = title,
        tags = tags,
        notes = notes,
        priority = priority,
        dueAt = dueAt,
        progress = progress,
        images = images,
        voiceNotes = voiceNotes,
        documents = documents,
        videos = videos,
        contacts = contacts,
        blockedByTaskId = blockedByTaskId,
        linkedSketchId = linkedSketchId,
        actionLog = actionLog,
        waitingOnName = waitingOnName,
        waitingOnSince = waitingOnSince,
        waitingOnFollowUpDays = waitingOnFollowUpDays,
        reminderEnabled = reminderEnabled,
        reminderAmount = reminderAmount,
        reminderUnit = reminderUnit,
        repeatEnabled = repeatEnabled,
        repeatOption = repeatOption
    )

    // Computed fresh at call time (never cached in a val) so it reads live state even if the
    // enclosing composable's lambda closures weren't recomposed since the last keystroke.
    fun isDirty() = initialSnapshot != null && initialSnapshot != currentSnapshot()

    val notificationPermissionLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestPermission()
    ) { granted -> reminderEnabled = granted }

    // Navigating to a pushed sub-screen (e.g. opening a linked sketch) and back disposes and
    // recomposes this screen from scratch, so a plain LaunchedEffect(taskId) would re-fire and
    // clobber any in-progress unsaved edits with the stale DB row. Guard it to run only once per
    // true first entry — rememberSaveable(taskId) survives that dispose/recompose correctly.
    var hasLoaded by rememberSaveable(taskId) { mutableStateOf(false) }
    LaunchedEffect(taskId) {
        if (isEditing) {
            // loadedTask is a plain `remember`, so it doesn't survive the dispose/recompose from
            // sub-navigation the way rememberSaveable does — always refresh it (harmless, doesn't
            // touch any user-facing field) so performSave() never mistakes an existing strip for a
            // new one and duplicates it. Only the editable fields below are guarded by hasLoaded.
            val t = viewModel.getTask(taskId)
            if (t != null) loadedTask = t
            if (!hasLoaded && t != null) {
                title = t.title
                tags = t.tags
                notes = t.notes
                priority = t.priority
                dueAt = t.dueAt
                progress = t.progress.toFloat()
                images = t.images
                voiceNotes = t.voiceNotes
                documents = t.documents
                videos = t.videos
                contacts = t.contacts
                blockedByTaskId = t.blockedByTaskId
                linkedSketchId = t.linkedSketchId
                actionLog = t.actionLog
                waitingOnName = t.waitingOnName
                waitingOnSince = t.waitingOnSince
                waitingOnFollowUpDays = t.waitingOnFollowUpDays
                t.reminderMinutesBefore?.let { minutes ->
                    reminderEnabled = true
                    val (amount, unit) = minutesToAmountAndUnit(minutes)
                    reminderAmount = amount.toString()
                    reminderUnit = unit
                }
                t.repeatIntervalDays?.let { days ->
                    repeatEnabled = true
                    repeatOption = daysToRepeatOption(days)
                }
            }
        } else if (!hasLoaded && title.isBlank()) {
            // Only apply on a genuinely empty draft — avoids clobbering rememberSaveable-restored
            // input if the process died and got recreated mid-edit.
            viewModel.consumePendingDraft()?.let { draft ->
                title = draft.title
                notes = draft.notes
                draft.priority?.let { priority = it }
                if (draft.contactEmail != null || draft.contactPhone != null) {
                    contacts = contacts + TaskContact(
                        name = draft.title,
                        email = draft.contactEmail.orEmpty(),
                        phone = draft.contactPhone.orEmpty()
                    )
                }
            }
        }
        if (!hasLoaded) {
            initialSnapshot = currentSnapshot()
            hasLoaded = true
        }
    }

    fun currentReminderMinutes(): Int? =
        if (reminderEnabled && dueAt != null) {
            (reminderAmount.toIntOrNull() ?: 0).coerceAtLeast(1) * reminderUnit.minutesPer
        } else {
            null
        }

    fun currentRepeatDays(): Int? = if (repeatEnabled && dueAt != null) repeatOption.days else null

    fun addTag() {
        val trimmed = tagInput.trim()
        if (trimmed.isNotEmpty() && tags.none { it.equals(trimmed, ignoreCase = true) }) {
            tags = tags + trimmed
        }
        tagInput = ""
    }

    fun snapshotForShare(): TaskEntity =
        (loadedTask ?: TaskEntity(title = "", orderIndex = 0)).copy(
            title = title.trim(),
            tags = tags,
            notes = notes.trim(),
            priority = priority,
            dueAt = dueAt,
            progress = progress.roundToInt(),
            images = images,
            voiceNotes = voiceNotes,
            contacts = contacts
        )

    // Shared by the SAVE button and the unsaved-changes prompt so both write identically.
    fun performSave(): Boolean {
        if (title.isBlank()) return false
        val existing = loadedTask
        val reminderMinutes = currentReminderMinutes()
        val repeatDays = currentRepeatDays()
        if (isEditing && existing != null) {
            viewModel.updateTask(
                existing.copy(
                    title = title.trim(),
                    tags = tags,
                    notes = notes.trim(),
                    priority = priority,
                    dueAt = dueAt,
                    progress = progress.roundToInt(),
                    images = images,
                    voiceNotes = voiceNotes,
                    documents = documents,
                    videos = videos,
                    reminderMinutesBefore = reminderMinutes,
                    repeatIntervalDays = repeatDays,
                    contacts = contacts,
                    blockedByTaskId = blockedByTaskId,
                    linkedSketchId = linkedSketchId,
                    actionLog = actionLog,
                    waitingOnName = waitingOnName,
                    waitingOnSince = waitingOnSince,
                    waitingOnFollowUpDays = waitingOnFollowUpDays
                )
            )
        } else {
            viewModel.addTask(
                title.trim(),
                "",
                notes.trim(),
                priority,
                dueAt,
                progress.roundToInt(),
                images,
                voiceNotes,
                documents,
                videos,
                reminderMinutes,
                repeatDays,
                contacts,
                tags,
                linkedSketchId,
                actionLog
            )
        }
        return true
    }

    fun handleBack() {
        if (isDirty()) showExitConfirm = true else onDone()
    }

    BackHandler(onBack = ::handleBack)

    Scaffold(
        containerColor = BayBackground,
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        text = if (isEditing) "EDIT STRIP" else "NEW STRIP",
                        style = MaterialTheme.typography.titleLarge,
                        color = Paper
                    )
                },
                navigationIcon = {
                    IconButton(onClick = ::handleBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back", tint = Paper)
                    }
                },
                actions = {
                    if (title.isNotBlank()) {
                        IconButton(onClick = { ShareImageRenderer.shareTask(context, snapshotForShare()) }) {
                            Icon(Icons.Default.Share, contentDescription = "Share as image", tint = Paper)
                        }
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = BayBackground)
            )
        },
        bottomBar = {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(BayBackground)
                    .windowInsetsPadding(WindowInsets.navigationBars)
                    .padding(horizontal = 20.dp, vertical = 12.dp)
            ) {
                Button(
                    onClick = { if (performSave()) onDone() },
                    colors = ButtonDefaults.buttonColors(containerColor = priority.tabColor(), contentColor = Paper),
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(52.dp)
                ) {
                    Text(
                        text = if (isEditing) "UPDATE STRIP" else "FILE STRIP",
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
                        Text("DELETE STRIP", color = PriorityUrgent, style = MaterialTheme.typography.bodyLarge)
                    }
                }
            }
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
                label = { Text("TASK") },
                singleLine = true,
                textStyle = LocalTextStyle.current.copy(fontFamily = FontFamily.Monospace),
                modifier = Modifier.fillMaxWidth()
            )
            Spacer(Modifier.height(14.dp))
            OutlinedTextField(
                value = tagInput,
                onValueChange = { tagInput = it },
                label = { Text("TAGS (optional)") },
                singleLine = true,
                textStyle = LocalTextStyle.current.copy(fontFamily = FontFamily.Monospace),
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                keyboardActions = KeyboardActions(onDone = { addTag() }),
                trailingIcon = {
                    IconButton(onClick = { addTag() }) {
                        Icon(Icons.Default.Add, contentDescription = "Add tag")
                    }
                },
                modifier = Modifier.fillMaxWidth()
            )
            if (tags.isNotEmpty()) {
                Spacer(Modifier.height(8.dp))
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    tags.forEach { tag ->
                        InputChip(
                            selected = false,
                            onClick = { tags = tags - tag },
                            label = { Text(tag.uppercase()) },
                            trailingIcon = {
                                Icon(
                                    Icons.Default.Close,
                                    contentDescription = "Remove tag $tag",
                                    modifier = Modifier.size(16.dp)
                                )
                            }
                        )
                    }
                }
            }
            Spacer(Modifier.height(18.dp))
            Text("PRIORITY", style = MaterialTheme.typography.labelSmall, color = Paper.copy(alpha = 0.7f))
            Spacer(Modifier.height(6.dp))
            SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                Priority.entries.forEachIndexed { index, p ->
                    SegmentedButton(
                        selected = priority == p,
                        onClick = { priority = p },
                        shape = SegmentedButtonDefaults.itemShape(index = index, count = Priority.entries.size),
                        colors = SegmentedButtonDefaults.colors(
                            activeContainerColor = p.tabColor(),
                            activeContentColor = Paper
                        )
                    ) {
                        Text(p.label, style = MaterialTheme.typography.bodyMedium)
                    }
                }
            }
            Spacer(Modifier.height(18.dp))
            Text("DUE DATE", style = MaterialTheme.typography.labelSmall, color = Paper.copy(alpha = 0.7f))
            Spacer(Modifier.height(6.dp))
            OutlinedButton(onClick = { showDatePicker = true }, modifier = Modifier.fillMaxWidth()) {
                Text(
                    text = dueAt?.let { formatEtaFull(it) } ?: "SET DUE DATE & TIME",
                    style = MaterialTheme.typography.bodyLarge
                )
            }
            if (dueAt != null) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    TextButton(onClick = { dueAt = null; reminderEnabled = false }) {
                        Text("CLEAR DUE DATE", style = MaterialTheme.typography.bodyMedium)
                    }
                    TextButton(onClick = {
                        val begin = dueAtAsLocalInstant(dueAt!!)
                        val intent = Intent(Intent.ACTION_INSERT, CalendarContract.Events.CONTENT_URI).apply {
                            putExtra(CalendarContract.Events.TITLE, title.ifBlank { "Task Strip" })
                            putExtra(CalendarContract.Events.DESCRIPTION, notes)
                            putExtra(CalendarContract.EXTRA_EVENT_BEGIN_TIME, begin)
                            putExtra(CalendarContract.EXTRA_EVENT_END_TIME, begin + 60 * 60 * 1000)
                        }
                        try {
                            context.startActivity(intent)
                        } catch (e: ActivityNotFoundException) {
                            Toast.makeText(context, "No calendar app found on this device", Toast.LENGTH_SHORT).show()
                        }
                    }) {
                        Icon(Icons.Default.CalendarMonth, contentDescription = null, tint = AmberTab, modifier = Modifier.width(18.dp))
                        Spacer(Modifier.width(6.dp))
                        Text("ADD TO CALENDAR", style = MaterialTheme.typography.bodyMedium)
                    }
                }

                Spacer(Modifier.height(10.dp))
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(
                        text = "REMIND ME",
                        style = MaterialTheme.typography.labelSmall,
                        color = Paper.copy(alpha = 0.7f),
                        modifier = Modifier.weight(1f)
                    )
                    Switch(
                        checked = reminderEnabled,
                        onCheckedChange = { checked ->
                            val needsPermission = checked &&
                                Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                                ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) !=
                                PackageManager.PERMISSION_GRANTED
                            if (needsPermission) {
                                notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
                            } else {
                                reminderEnabled = checked
                            }
                        },
                        colors = SwitchDefaults.colors(checkedThumbColor = AmberTab, checkedTrackColor = AmberTab.copy(alpha = 0.5f))
                    )
                }
                if (reminderEnabled) {
                    Spacer(Modifier.height(8.dp))
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        OutlinedTextField(
                            value = reminderAmount,
                            onValueChange = { value -> reminderAmount = value.filter { it.isDigit() }.take(4) },
                            singleLine = true,
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                            textStyle = LocalTextStyle.current.copy(fontFamily = FontFamily.Monospace),
                            modifier = Modifier.width(90.dp)
                        )
                        Spacer(Modifier.width(10.dp))
                        SingleChoiceSegmentedButtonRow(Modifier.weight(1f)) {
                            ReminderUnit.entries.forEachIndexed { index, unit ->
                                SegmentedButton(
                                    selected = reminderUnit == unit,
                                    onClick = { reminderUnit = unit },
                                    shape = SegmentedButtonDefaults.itemShape(index = index, count = ReminderUnit.entries.size)
                                ) {
                                    Text(unit.label, style = MaterialTheme.typography.bodyMedium)
                                }
                            }
                        }
                    }
                    Text(
                        text = "Notified $reminderAmount ${reminderUnit.label.lowercase()} before due",
                        style = MaterialTheme.typography.labelSmall,
                        color = Paper.copy(alpha = 0.5f),
                        modifier = Modifier.padding(top = 6.dp)
                    )
                }

                Spacer(Modifier.height(10.dp))
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(
                        text = "REPEAT",
                        style = MaterialTheme.typography.labelSmall,
                        color = Paper.copy(alpha = 0.7f),
                        modifier = Modifier.weight(1f)
                    )
                    Switch(
                        checked = repeatEnabled,
                        onCheckedChange = { repeatEnabled = it },
                        colors = SwitchDefaults.colors(checkedThumbColor = AmberTab, checkedTrackColor = AmberTab.copy(alpha = 0.5f))
                    )
                }
                if (repeatEnabled) {
                    Spacer(Modifier.height(8.dp))
                    SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                        RepeatOption.entries.forEachIndexed { index, option ->
                            SegmentedButton(
                                selected = repeatOption == option,
                                onClick = { repeatOption = option },
                                shape = SegmentedButtonDefaults.itemShape(index = index, count = RepeatOption.entries.size)
                            ) {
                                Text(option.label, style = MaterialTheme.typography.bodyMedium)
                            }
                        }
                    }
                    Text(
                        text = "Completing this strip files the next one, due date shifted forward",
                        style = MaterialTheme.typography.labelSmall,
                        color = Paper.copy(alpha = 0.5f),
                        modifier = Modifier.padding(top = 6.dp)
                    )
                }
            }
            Spacer(Modifier.height(18.dp))
            Text(
                text = "PROGRESS: ${progress.roundToInt()}%",
                style = MaterialTheme.typography.labelSmall,
                color = Paper.copy(alpha = 0.7f)
            )
            Slider(
                value = progress,
                onValueChange = { progress = it },
                valueRange = 0f..100f,
                steps = 19,
                colors = SliderDefaults.colors(thumbColor = priority.tabColor(), activeTrackColor = priority.tabColor())
            )
            Spacer(Modifier.height(10.dp))
            OutlinedTextField(
                value = notes,
                onValueChange = { notes = it },
                label = { Text("NOTES") },
                textStyle = LocalTextStyle.current.copy(fontFamily = FontFamily.Monospace),
                trailingIcon = {
                    IconButton(onClick = { showNotesEditor = true }) {
                        Icon(Icons.Default.Fullscreen, contentDescription = "Expand notes")
                    }
                },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(120.dp)
            )
            Spacer(Modifier.height(18.dp))
            AttachmentsSection(
                images = images,
                onImagesChange = { images = it },
                voiceNotes = voiceNotes,
                onVoiceNotesChange = { voiceNotes = it },
                documents = documents,
                onDocumentsChange = { documents = it },
                videos = videos,
                onVideosChange = { videos = it }
            )
            Spacer(Modifier.height(18.dp))
            ContactsSection(
                contacts = contacts,
                onContactsChange = { contacts = it }
            )
            Spacer(Modifier.height(18.dp))
            SketchLinkSection(
                linkedSketchId = linkedSketchId,
                onLinkedSketchChange = { linkedSketchId = it },
                onOpenSketch = onOpenSketch
            )
            if (isEditing) {
                Spacer(Modifier.height(18.dp))
                BlockedBySection(
                    allTasks = allTasksForPicker,
                    currentTaskId = taskId,
                    blockedByTaskId = blockedByTaskId,
                    onBlockedByChange = { blockedByTaskId = it }
                )
                Spacer(Modifier.height(18.dp))
                DelegateSection(
                    contacts = contacts,
                    waitingOnName = waitingOnName,
                    waitingOnFollowUpDays = waitingOnFollowUpDays,
                    onDelegate = { name, days ->
                        waitingOnName = name
                        waitingOnSince = System.currentTimeMillis()
                        waitingOnFollowUpDays = days
                    },
                    onClear = {
                        waitingOnName = ""
                        waitingOnSince = null
                        waitingOnFollowUpDays = null
                    }
                )
            }
            Spacer(Modifier.height(18.dp))
            ActionLogSection(
                actionLog = actionLog,
                onAddAction = { text ->
                    actionLog = actionLog + TaskActionLogEntry(text.trim(), System.currentTimeMillis())
                },
                onRemoveAction = { entry -> actionLog = actionLog - entry }
            )
            // Save/Delete live in the Scaffold's bottomBar (below) so they stay fixed at the
            // bottom of the screen instead of scrolling away with the form.
            Spacer(Modifier.height(20.dp))
        }
    }

    if (showDeleteConfirm) {
        AlertDialog(
            onDismissRequest = { showDeleteConfirm = false },
            title = { Text("DELETE STRIP?", style = MaterialTheme.typography.titleMedium) },
            text = { Text("\"${title.ifBlank { "This strip" }}\" and its attachments will be permanently deleted. This can't be undone.") },
            confirmButton = {
                TextButton(onClick = {
                    showDeleteConfirm = false
                    loadedTask?.let { viewModel.deleteTask(it) }
                    onDone()
                }) { Text("DELETE", color = PriorityUrgent) }
            },
            dismissButton = {
                TextButton(onClick = { showDeleteConfirm = false }) { Text("CANCEL") }
            }
        )
    }

    if (showExitConfirm) {
        AlertDialog(
            onDismissRequest = { showExitConfirm = false },
            title = { Text("UNSAVED CHANGES", style = MaterialTheme.typography.titleMedium) },
            text = { Text("This strip has changes that haven't been saved. Save before leaving?") },
            confirmButton = {
                TextButton(onClick = {
                    showExitConfirm = false
                    if (performSave()) onDone()
                }) { Text("SAVE") }
            },
            dismissButton = {
                Row {
                    TextButton(onClick = {
                        showExitConfirm = false
                        onDone()
                    }) { Text("DISCARD", color = PriorityUrgent) }
                    TextButton(onClick = { showExitConfirm = false }) { Text("CANCEL") }
                }
            }
        )
    }

    if (showNotesEditor) {
        NotesEditorDialog(
            notes = notes,
            onNotesChange = { notes = it },
            onDismiss = { showNotesEditor = false }
        )
    }

    if (showDatePicker) {
        val state = rememberDatePickerState(initialSelectedDateMillis = dueAt ?: System.currentTimeMillis())
        DatePickerDialog(
            onDismissRequest = { showDatePicker = false },
            confirmButton = {
                TextButton(onClick = {
                    pendingDateMillis = state.selectedDateMillis
                    showDatePicker = false
                    showTimePicker = true
                }) { Text("NEXT") }
            },
            dismissButton = {
                TextButton(onClick = { showDatePicker = false }) { Text("CANCEL") }
            }
        ) {
            DatePicker(state = state)
        }
    }

    if (showTimePicker) {
        val timeState = rememberTimePickerState(is24Hour = true)
        AlertDialog(
            onDismissRequest = { showTimePicker = false },
            confirmButton = {
                TextButton(onClick = {
                    val base = pendingDateMillis ?: System.currentTimeMillis()
                    val zdt = Instant.ofEpochMilli(base).atZone(ZoneOffset.UTC)
                        .withHour(timeState.hour)
                        .withMinute(timeState.minute)
                    dueAt = zdt.toInstant().toEpochMilli()
                    showTimePicker = false
                }) { Text("SET") }
            },
            dismissButton = {
                TextButton(onClick = { showTimePicker = false }) { Text("CANCEL") }
            },
            text = { TimePicker(state = timeState) }
        )
    }
}

// Matches a checklist line written as "[ ] text" or "[✓] text" — the plain-text syntax the user
// types directly into notes, so checklists survive as ordinary text (backups, sharing, etc.)
// instead of needing a separate data model. "x"/"X" is still accepted when parsing so notes
// written before this marker changed to a checkmark keep working.
private val checklistLineRegex = Regex("^\\[([ xX✓])]\\s?(.*)$")

private fun toggleChecklistLine(notes: String, lineIndex: Int): String {
    val lines = notes.split("\n").toMutableList()
    val line = lines.getOrNull(lineIndex) ?: return notes
    val match = checklistLineRegex.find(line) ?: return notes
    val isChecked = match.groupValues[1] != " "
    val content = match.groupValues[2]
    lines[lineIndex] = "${if (isChecked) "[ ]" else "[✓]"} $content"
    return lines.joinToString("\n")
}

@Composable
private fun NotesEditorDialog(
    notes: String,
    onNotesChange: (String) -> Unit,
    onDismiss: () -> Unit
) {
    var checklistViewMode by rememberSaveable { mutableStateOf(false) }
    var fieldValue by remember { mutableStateOf(TextFieldValue(notes)) }
    var requestNotesFocus by remember { mutableStateOf(false) }
    val focusRequester = remember { FocusRequester() }

    // Resyncs the controlled field when notes changed from outside normal typing (a checklist
    // toggle in view mode) — a no-op after ordinary keystrokes, since those already keep
    // fieldValue.text and notes equal.
    LaunchedEffect(notes) {
        if (notes != fieldValue.text) {
            fieldValue = TextFieldValue(notes, selection = TextRange(notes.length))
        }
    }

    // Requesting focus must wait until the text field is actually back in composition — calling
    // it synchronously from the "add item" button crashes when that tap starts in checklist view,
    // since the field (and its FocusRequester attachment) doesn't exist yet at that instant.
    LaunchedEffect(requestNotesFocus) {
        if (requestNotesFocus) {
            focusRequester.requestFocus()
            requestNotesFocus = false
        }
    }

    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Column(
            Modifier
                .fillMaxSize()
                .background(BayBackground)
                .windowInsetsPadding(WindowInsets.systemBars)
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 8.dp, vertical = 4.dp)
            ) {
                IconButton(onClick = onDismiss) {
                    Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Close", tint = Paper)
                }
                Text(
                    text = "NOTES",
                    style = MaterialTheme.typography.titleMedium,
                    color = Paper,
                    modifier = Modifier.weight(1f)
                )
                IconButton(onClick = {
                    val trimmed = notes.trimEnd('\n')
                    val appended = if (trimmed.isBlank()) "[ ] " else "$trimmed\n[ ] "
                    fieldValue = TextFieldValue(appended, selection = TextRange(appended.length))
                    onNotesChange(appended)
                    checklistViewMode = false
                    requestNotesFocus = true
                }) {
                    Icon(Icons.Default.AddTask, contentDescription = "Add checklist item", tint = Paper)
                }
                IconButton(onClick = { checklistViewMode = !checklistViewMode }) {
                    Icon(
                        imageVector = if (checklistViewMode) Icons.Default.EditNote else Icons.Default.Checklist,
                        contentDescription = if (checklistViewMode) "Switch to text editing" else "Switch to checklist view",
                        tint = Paper
                    )
                }
            }
            if (checklistViewMode) {
                Column(
                    Modifier
                        .fillMaxWidth()
                        .weight(1f)
                        .verticalScroll(rememberScrollState())
                        .padding(horizontal = 16.dp, vertical = 8.dp)
                ) {
                    notes.split("\n").forEachIndexed { index, line ->
                        val match = checklistLineRegex.find(line)
                        if (match != null) {
                            val isChecked = match.groupValues[1] != " "
                            val content = match.groupValues[2]
                            Row(
                                verticalAlignment = Alignment.CenterVertically,
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .clickable { onNotesChange(toggleChecklistLine(notes, index)) }
                            ) {
                                Checkbox(
                                    checked = isChecked,
                                    onCheckedChange = { onNotesChange(toggleChecklistLine(notes, index)) },
                                    colors = CheckboxDefaults.colors(checkedColor = AmberTab, uncheckedColor = Paper.copy(alpha = 0.6f))
                                )
                                Text(
                                    text = content,
                                    style = MaterialTheme.typography.bodyLarge.copy(
                                        fontFamily = FontFamily.Monospace,
                                        textDecoration = if (isChecked) TextDecoration.LineThrough else null
                                    ),
                                    color = if (isChecked) Paper.copy(alpha = 0.45f) else Paper
                                )
                            }
                        } else if (line.isNotBlank()) {
                            Text(
                                text = line,
                                style = MaterialTheme.typography.bodyLarge.copy(fontFamily = FontFamily.Monospace),
                                color = Paper,
                                modifier = Modifier.padding(vertical = 12.dp, horizontal = 12.dp)
                            )
                        }
                    }
                }
            } else {
                OutlinedTextField(
                    value = fieldValue,
                    onValueChange = { newValue ->
                        fieldValue = newValue
                        onNotesChange(newValue.text)
                    },
                    placeholder = { Text("Tip: start a line with [ ] to make it a checklist item") },
                    textStyle = LocalTextStyle.current.copy(fontFamily = FontFamily.Monospace),
                    modifier = Modifier
                        .fillMaxWidth()
                        .weight(1f)
                        .padding(horizontal = 16.dp, vertical = 8.dp)
                        .focusRequester(focusRequester)
                )
            }
        }
    }
}

@Composable
private fun BlockedBySection(
    allTasks: List<TaskEntity>,
    currentTaskId: Long,
    blockedByTaskId: Long?,
    onBlockedByChange: (Long?) -> Unit
) {
    var showPicker by remember { mutableStateOf(false) }
    val blocker = allTasks.find { it.id == blockedByTaskId }

    Text("BLOCKED BY (optional)", style = MaterialTheme.typography.labelSmall, color = Paper.copy(alpha = 0.7f))
    Spacer(Modifier.height(6.dp))
    if (blocker != null) {
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
            Icon(Icons.Default.Block, contentDescription = null, tint = PriorityUrgent)
            Spacer(Modifier.width(8.dp))
            Text(
                text = blocker.title.uppercase(),
                style = MaterialTheme.typography.bodyMedium,
                color = Paper,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f)
            )
            IconButton(onClick = { onBlockedByChange(null) }) {
                Icon(Icons.Default.Close, contentDescription = "Clear blocker", tint = Paper.copy(alpha = 0.6f))
            }
        }
    } else {
        OutlinedButton(onClick = { showPicker = true }, modifier = Modifier.height(48.dp)) {
            Icon(Icons.Default.Block, contentDescription = null, tint = Paper.copy(alpha = 0.7f))
            Spacer(Modifier.width(8.dp))
            Text("SELECT BLOCKING STRIP", style = MaterialTheme.typography.bodyMedium)
        }
    }

    if (showPicker) {
        val candidates = allTasks.filter { it.id != currentTaskId && !it.isDone && !it.isArchived }
        AlertDialog(
            onDismissRequest = { showPicker = false },
            title = { Text("SELECT BLOCKING STRIP", style = MaterialTheme.typography.titleMedium) },
            text = {
                if (candidates.isEmpty()) {
                    Text("No other open strips to block on.")
                } else {
                    Column(Modifier.heightIn(max = 320.dp).verticalScroll(rememberScrollState())) {
                        candidates.forEach { c ->
                            Text(
                                text = c.title.uppercase(),
                                style = MaterialTheme.typography.bodyMedium,
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .clickable {
                                        onBlockedByChange(c.id)
                                        showPicker = false
                                    }
                                    .padding(vertical = 10.dp)
                            )
                        }
                    }
                }
            },
            confirmButton = {
                TextButton(onClick = { showPicker = false }) { Text("CANCEL") }
            }
        )
    }
}

@Composable
private fun SketchLinkSection(
    linkedSketchId: String?,
    onLinkedSketchChange: (String?) -> Unit,
    onOpenSketch: (String) -> Unit
) {
    val context = LocalContext.current
    var showPicker by remember { mutableStateOf(false) }

    Text("LINKED SKETCH (optional)", style = MaterialTheme.typography.labelSmall, color = Paper.copy(alpha = 0.7f))
    Spacer(Modifier.height(6.dp))

    if (linkedSketchId != null) {
        val note = remember(linkedSketchId) { SketchStorage.noteRef(context, linkedSketchId) }
        // Not `remember`-cached — File.equals() only compares paths, so a rename wouldn't
        // invalidate a cached label; this is a cheap local read anyway.
        val label = if (SketchStorage.listPages(note).isNotEmpty()) SketchStorage.displayLabel(note) else "Sketch note"
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier
                .fillMaxWidth()
                .clickable { onOpenSketch(linkedSketchId) }
        ) {
            Icon(Icons.Default.Draw, contentDescription = null, tint = AmberTab)
            Spacer(Modifier.width(8.dp))
            Text(
                text = label,
                style = MaterialTheme.typography.bodyMedium,
                color = Paper,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f)
            )
            IconButton(onClick = { onLinkedSketchChange(null) }) {
                Icon(Icons.Default.Close, contentDescription = "Unlink sketch", tint = Paper.copy(alpha = 0.6f))
            }
        }
    } else {
        OutlinedButton(onClick = { showPicker = true }, modifier = Modifier.height(48.dp)) {
            Icon(Icons.Default.Draw, contentDescription = null, tint = Paper.copy(alpha = 0.7f))
            Spacer(Modifier.width(8.dp))
            Text("LINK SKETCH", style = MaterialTheme.typography.bodyMedium)
        }
    }

    if (showPicker) {
        val notes = remember { SketchStorage.listNotes(context) }
        AlertDialog(
            onDismissRequest = { showPicker = false },
            title = { Text("LINK A SKETCH", style = MaterialTheme.typography.titleMedium) },
            text = {
                if (notes.isEmpty()) {
                    Text("No sketches yet. Create one from the Sketches list first.")
                } else {
                    Column(Modifier.heightIn(max = 320.dp).verticalScroll(rememberScrollState())) {
                        notes.forEach { note ->
                            Column(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .clickable {
                                        onLinkedSketchChange(note.name)
                                        showPicker = false
                                    }
                                    .padding(vertical = 10.dp)
                            ) {
                                Text(
                                    text = SketchStorage.displayLabel(note),
                                    style = MaterialTheme.typography.bodyMedium
                                )
                                Text(
                                    text = "Created ${SketchStorage.createdLabel(note)}",
                                    style = MaterialTheme.typography.labelSmall,
                                    color = Paper.copy(alpha = 0.6f)
                                )
                            }
                        }
                    }
                }
            },
            confirmButton = {
                TextButton(onClick = { showPicker = false }) { Text("CANCEL") }
            }
        )
    }
}

@Composable
private fun ActionLogSection(
    actionLog: List<TaskActionLogEntry>,
    onAddAction: (String) -> Unit,
    onRemoveAction: (TaskActionLogEntry) -> Unit
) {
    var input by rememberSaveable { mutableStateOf("") }
    var pendingRemoval by remember { mutableStateOf<TaskActionLogEntry?>(null) }

    fun submit() {
        val trimmed = input.trim()
        if (trimmed.isNotEmpty()) {
            onAddAction(trimmed)
            input = ""
        }
    }

    Text("ACTIVITY LOG (optional)", style = MaterialTheme.typography.labelSmall, color = Paper.copy(alpha = 0.7f))
    Spacer(Modifier.height(6.dp))
    Row(verticalAlignment = Alignment.CenterVertically) {
        OutlinedTextField(
            value = input,
            onValueChange = { input = it },
            placeholder = { Text("Log an action…") },
            singleLine = true,
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
            keyboardActions = KeyboardActions(onDone = { submit() }),
            modifier = Modifier.weight(1f)
        )
        Spacer(Modifier.width(8.dp))
        IconButton(onClick = { submit() }) {
            Icon(Icons.Default.Add, contentDescription = "Add log entry", tint = AmberTab)
        }
    }

    if (actionLog.isNotEmpty()) {
        Spacer(Modifier.height(10.dp))
        // Newest first — the whole point of the log is seeing what just happened at a glance.
        val sorted = remember(actionLog) { actionLog.sortedByDescending { it.timestamp } }
        Column {
            sorted.forEach { entry ->
                Row(
                    verticalAlignment = Alignment.Top,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(vertical = 6.dp)
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            text = entry.text,
                            style = MaterialTheme.typography.bodyMedium,
                            color = Paper
                        )
                        Text(
                            text = formatTimestampFull(entry.timestamp),
                            style = MaterialTheme.typography.labelSmall,
                            color = Paper.copy(alpha = 0.5f)
                        )
                    }
                    IconButton(
                        onClick = { pendingRemoval = entry },
                        modifier = Modifier.size(32.dp)
                    ) {
                        Icon(
                            Icons.Default.Close,
                            contentDescription = "Remove log entry",
                            tint = Paper.copy(alpha = 0.5f),
                            modifier = Modifier.size(16.dp)
                        )
                    }
                }
                if (entry != sorted.last()) {
                    HorizontalDivider(color = InkColor.copy(alpha = 0.1f))
                }
            }
        }
    }

    pendingRemoval?.let { entry ->
        AlertDialog(
            onDismissRequest = { pendingRemoval = null },
            title = { Text("DELETE LOG ENTRY?", style = MaterialTheme.typography.titleMedium) },
            text = { Text("\"${entry.text}\" will be permanently deleted. This can't be undone.") },
            confirmButton = {
                TextButton(onClick = {
                    onRemoveAction(entry)
                    pendingRemoval = null
                }) { Text("DELETE", color = PriorityUrgent) }
            },
            dismissButton = {
                TextButton(onClick = { pendingRemoval = null }) { Text("CANCEL") }
            }
        )
    }
}

@OptIn(ExperimentalLayoutApi::class, androidx.compose.foundation.ExperimentalFoundationApi::class)
@Composable
private fun DelegateSection(
    contacts: List<TaskContact>,
    waitingOnName: String,
    waitingOnFollowUpDays: Int?,
    onDelegate: (name: String, days: Int) -> Unit,
    onClear: () -> Unit
) {
    Text("DELEGATE (optional)", style = MaterialTheme.typography.labelSmall, color = Paper.copy(alpha = 0.7f))
    Spacer(Modifier.height(6.dp))

    if (waitingOnName.isNotBlank()) {
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
            Icon(Icons.Default.HourglassTop, contentDescription = null, tint = AmberTab)
            Spacer(Modifier.width(8.dp))
            Text(
                text = "Waiting on $waitingOnName" + (waitingOnFollowUpDays?.let { " · follow up in $it d" } ?: ""),
                style = MaterialTheme.typography.bodyMedium,
                color = Paper,
                modifier = Modifier.weight(1f)
            )
            IconButton(onClick = onClear) {
                Icon(Icons.Default.Close, contentDescription = "Clear delegation", tint = Paper.copy(alpha = 0.6f))
            }
        }
    } else if (contacts.isEmpty()) {
        Text(
            text = "Add a contact above to delegate this strip.",
            style = MaterialTheme.typography.bodyMedium,
            color = Paper.copy(alpha = 0.5f)
        )
    } else {
        var selectedContact by remember { mutableStateOf<TaskContact?>(null) }
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            contacts.forEach { c ->
                FilterChip(
                    selected = selectedContact == c,
                    onClick = { selectedContact = c },
                    label = { Text(c.name.uppercase()) }
                )
            }
        }
        if (selectedContact != null) {
            // Picking a contact reveals this row below the fold — scroll it into view so it
            // doesn't end up hidden behind the fixed save/delete bar with no visual cue.
            val bringIntoViewRequester = remember { BringIntoViewRequester() }
            LaunchedEffect(selectedContact) {
                bringIntoViewRequester.bringIntoView()
            }
            Spacer(Modifier.height(10.dp))
            Text("FOLLOW UP IN", style = MaterialTheme.typography.labelSmall, color = Paper.copy(alpha = 0.5f))
            Spacer(Modifier.height(4.dp))
            Row(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                modifier = Modifier.bringIntoViewRequester(bringIntoViewRequester)
            ) {
                listOf(1, 3, 7).forEach { days ->
                    OutlinedButton(onClick = { onDelegate(selectedContact!!.name, days) }) {
                        Text("$days D")
                    }
                }
            }
        }
    }
}
