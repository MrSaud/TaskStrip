package com.saud.taskstrip.ui.screens

import android.content.ActivityNotFoundException
import android.content.Intent
import android.provider.CalendarContract
import android.widget.Toast
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LocalTextStyle
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.layout.Arrangement
import com.saud.taskstrip.ReminderViewModel
import com.saud.taskstrip.data.ReminderEntity
import com.saud.taskstrip.ui.components.dueAtAsLocalInstant
import com.saud.taskstrip.ui.components.formatEtaFull
import com.saud.taskstrip.ui.theme.AmberTab
import com.saud.taskstrip.ui.theme.BayBackground
import com.saud.taskstrip.ui.theme.Paper
import com.saud.taskstrip.ui.theme.PriorityUrgent
import java.time.Instant
import java.time.ZoneOffset

private enum class LeadUnit(val label: String, val minutesPer: Int) {
    HOURS("HR", 60),
    DAYS("DAY", 1440)
}

private fun minutesToLeadAmountAndUnit(minutes: Int): Pair<Int, LeadUnit> = when {
    minutes >= 1440 && minutes % 1440 == 0 -> (minutes / 1440) to LeadUnit.DAYS
    else -> (minutes / 60).coerceAtLeast(1) to LeadUnit.HOURS
}

// Stored as repeatUnit.name (e.g. "DAILY") — calendar-accurate advancement happens in
// GeneralReminderReceiver, not here; this enum only drives the picker UI.
private enum class RepeatUnit(val label: String) {
    DAILY("DAY"),
    WEEKLY("WEEK"),
    MONTHLY("MONTH"),
    YEARLY("YEAR")
}

// Quick-pick starting points for the tag/emoji fields below — not a restricted set, just presets
// that fill both fields in one tap; the user can still type any tag name and emoji of their own.
private val TAG_PRESETS = listOf(
    "Birthday" to "🎂",
    "Service" to "🔧",
    "Documents" to "📄",
    "Bill" to "💳",
    "Appointment" to "📅",
    "Travel" to "✈️",
    "Health" to "💊",
    "Family" to "👪"
)

@OptIn(ExperimentalMaterial3Api::class, androidx.compose.foundation.layout.ExperimentalLayoutApi::class)
@Composable
fun ReminderEditScreen(
    viewModel: ReminderViewModel,
    reminderId: Long,
    onDone: () -> Unit
) {
    val context = LocalContext.current
    val isEditing = reminderId >= 0

    var text by rememberSaveable { mutableStateOf("") }
    var description by rememberSaveable { mutableStateOf("") }
    var tag by rememberSaveable { mutableStateOf("") }
    var tagEmoji by rememberSaveable { mutableStateOf("") }
    // Defaults an hour out for a brand-new reminder so it's a valid, obviously-editable starting
    // point rather than "now" (which would be in the past the instant the user pauses to think).
    var triggerAt by rememberSaveable { mutableStateOf(System.currentTimeMillis() + 60 * 60_000L) }
    var showDatePicker by rememberSaveable { mutableStateOf(false) }
    var showTimePicker by rememberSaveable { mutableStateOf(false) }
    var pendingDateMillis by rememberSaveable { mutableStateOf<Long?>(null) }
    var showDeleteConfirm by rememberSaveable { mutableStateOf(false) }
    var loadedReminder by remember { mutableStateOf<ReminderEntity?>(null) }
    var hasLoaded by rememberSaveable(reminderId) { mutableStateOf(false) }

    var notifyBeforeEnabled by rememberSaveable { mutableStateOf(false) }
    var leadAmount by rememberSaveable { mutableStateOf("1") }
    var leadUnit by rememberSaveable { mutableStateOf(LeadUnit.HOURS) }

    var repeatEnabled by rememberSaveable { mutableStateOf(false) }
    var repeatAmount by rememberSaveable { mutableStateOf("1") }
    var repeatUnit by rememberSaveable { mutableStateOf(RepeatUnit.DAILY) }

    LaunchedEffect(reminderId) {
        if (isEditing) {
            viewModel.getById(reminderId)?.let { r ->
                loadedReminder = r
                if (!hasLoaded) {
                    text = r.text
                    description = r.description
                    tag = r.tag
                    tagEmoji = r.tagEmoji
                    triggerAt = r.triggerAt
                    r.leadMinutesBefore?.let { minutes ->
                        notifyBeforeEnabled = true
                        val (amount, unit) = minutesToLeadAmountAndUnit(minutes)
                        leadAmount = amount.toString()
                        leadUnit = unit
                    }
                    r.repeatUnit?.let { unitName ->
                        RepeatUnit.entries.firstOrNull { it.name == unitName }?.let { unit ->
                            repeatEnabled = true
                            repeatUnit = unit
                            repeatAmount = (r.repeatAmount ?: 1).toString()
                        }
                    }
                }
            }
        } else if (!hasLoaded) {
            viewModel.consumePendingText()?.let { text = it }
        }
        hasLoaded = true
    }

    fun currentLeadMinutes(): Int? =
        if (notifyBeforeEnabled) (leadAmount.toIntOrNull() ?: 0).coerceAtLeast(1) * leadUnit.minutesPer else null

    fun currentRepeatAmount(): Int? = if (repeatEnabled) (repeatAmount.toIntOrNull() ?: 1).coerceAtLeast(1) else null
    fun currentRepeatUnit(): String? = if (repeatEnabled) repeatUnit.name else null

    Scaffold(
        containerColor = BayBackground,
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        text = if (isEditing) "EDIT REMINDER" else "NEW REMINDER",
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
                value = text,
                onValueChange = { text = it },
                label = { Text("TITLE") },
                singleLine = true,
                textStyle = LocalTextStyle.current.copy(fontFamily = FontFamily.Monospace),
                modifier = Modifier.fillMaxWidth()
            )
            Spacer(Modifier.height(14.dp))
            OutlinedTextField(
                value = description,
                onValueChange = { description = it },
                label = { Text("DETAILS (optional)") },
                textStyle = LocalTextStyle.current.copy(fontFamily = FontFamily.Monospace),
                modifier = Modifier.fillMaxWidth().height(120.dp)
            )
            Spacer(Modifier.height(14.dp))
            Row(verticalAlignment = Alignment.Top) {
                OutlinedTextField(
                    value = tag,
                    onValueChange = { tag = it },
                    label = { Text("TAG (optional)") },
                    singleLine = true,
                    textStyle = LocalTextStyle.current.copy(fontFamily = FontFamily.Monospace),
                    modifier = Modifier.weight(1f)
                )
                Spacer(Modifier.width(10.dp))
                OutlinedTextField(
                    value = tagEmoji,
                    onValueChange = { tagEmoji = it.take(4) },
                    label = { Text("EMOJI") },
                    singleLine = true,
                    textStyle = LocalTextStyle.current.copy(fontFamily = FontFamily.Monospace),
                    modifier = Modifier.width(96.dp)
                )
            }
            Spacer(Modifier.height(8.dp))
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                TAG_PRESETS.forEach { (presetTag, presetEmoji) ->
                    AssistChip(
                        onClick = { tag = presetTag; tagEmoji = presetEmoji },
                        label = { Text("$presetEmoji $presetTag") }
                    )
                }
            }
            Spacer(Modifier.height(18.dp))
            Text("WHEN", style = MaterialTheme.typography.labelSmall, color = Paper.copy(alpha = 0.7f))
            Spacer(Modifier.height(6.dp))
            OutlinedButton(onClick = { showDatePicker = true }, modifier = Modifier.fillMaxWidth()) {
                Text(text = formatEtaFull(triggerAt), style = MaterialTheme.typography.bodyLarge)
            }
            Spacer(Modifier.height(10.dp))
            TextButton(onClick = {
                val begin = dueAtAsLocalInstant(triggerAt)
                val intent = Intent(Intent.ACTION_INSERT, CalendarContract.Events.CONTENT_URI).apply {
                    putExtra(CalendarContract.Events.TITLE, text.ifBlank { "Reminder" })
                    putExtra(CalendarContract.Events.DESCRIPTION, description)
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
            Spacer(Modifier.height(10.dp))
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(
                    text = "NOTIFY ME BEFORE",
                    style = MaterialTheme.typography.labelSmall,
                    color = Paper.copy(alpha = 0.7f),
                    modifier = Modifier.weight(1f)
                )
                Switch(
                    checked = notifyBeforeEnabled,
                    onCheckedChange = { notifyBeforeEnabled = it },
                    colors = SwitchDefaults.colors(checkedThumbColor = AmberTab, checkedTrackColor = AmberTab.copy(alpha = 0.5f))
                )
            }
            if (notifyBeforeEnabled) {
                Spacer(Modifier.height(8.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    OutlinedTextField(
                        value = leadAmount,
                        onValueChange = { value -> leadAmount = value.filter { it.isDigit() }.take(4) },
                        singleLine = true,
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                        textStyle = LocalTextStyle.current.copy(fontFamily = FontFamily.Monospace),
                        modifier = Modifier.width(90.dp)
                    )
                    Spacer(Modifier.width(10.dp))
                    SingleChoiceSegmentedButtonRow(Modifier.weight(1f)) {
                        LeadUnit.entries.forEachIndexed { index, unit ->
                            SegmentedButton(
                                selected = leadUnit == unit,
                                onClick = { leadUnit = unit },
                                shape = SegmentedButtonDefaults.itemShape(index = index, count = LeadUnit.entries.size)
                            ) {
                                Text(unit.label, style = MaterialTheme.typography.bodyMedium)
                            }
                        }
                    }
                }
                Text(
                    text = "Notified $leadAmount ${leadUnit.label.lowercase()} before this reminder's time",
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
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("EVERY", style = MaterialTheme.typography.bodyMedium, color = Paper.copy(alpha = 0.7f))
                    Spacer(Modifier.width(10.dp))
                    OutlinedTextField(
                        value = repeatAmount,
                        onValueChange = { value -> repeatAmount = value.filter { it.isDigit() }.take(3) },
                        singleLine = true,
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                        textStyle = LocalTextStyle.current.copy(fontFamily = FontFamily.Monospace),
                        modifier = Modifier.width(80.dp)
                    )
                }
                Spacer(Modifier.height(8.dp))
                SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                    RepeatUnit.entries.forEachIndexed { index, unit ->
                        SegmentedButton(
                            selected = repeatUnit == unit,
                            onClick = { repeatUnit = unit },
                            shape = SegmentedButtonDefaults.itemShape(index = index, count = RepeatUnit.entries.size)
                        ) {
                            Text(unit.label, style = MaterialTheme.typography.bodyMedium)
                        }
                    }
                }
                val unitWord = repeatUnit.label.lowercase() + if (repeatAmount != "1") "s" else ""
                Text(
                    text = "Repeats every $repeatAmount $unitWord",
                    style = MaterialTheme.typography.labelSmall,
                    color = Paper.copy(alpha = 0.5f),
                    modifier = Modifier.padding(top = 6.dp)
                )
            }
            Spacer(Modifier.height(28.dp))
            Button(
                onClick = {
                    if (text.isNotBlank()) {
                        val leadMinutes = currentLeadMinutes()
                        val repeatAmountValue = currentRepeatAmount()
                        val repeatUnitValue = currentRepeatUnit()
                        val existing = loadedReminder
                        if (isEditing && existing != null) {
                            viewModel.update(
                                existing, text.trim(), description.trim(), triggerAt,
                                leadMinutes, repeatAmountValue, repeatUnitValue,
                                tag.trim(), tagEmoji.trim(), existing.isDone
                            )
                        } else {
                            viewModel.add(
                                text.trim(), description.trim(), triggerAt,
                                leadMinutes, repeatAmountValue, repeatUnitValue,
                                tag.trim(), tagEmoji.trim()
                            )
                        }
                        onDone()
                    }
                },
                colors = ButtonDefaults.buttonColors(containerColor = AmberTab, contentColor = Paper),
                modifier = Modifier.fillMaxWidth().height(52.dp)
            ) {
                Text(
                    text = if (isEditing) "UPDATE REMINDER" else "SAVE REMINDER",
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
                    Text("DELETE REMINDER", color = PriorityUrgent, style = MaterialTheme.typography.bodyLarge)
                }
            }
        }
    }

    if (showDatePicker) {
        val state = rememberDatePickerState(initialSelectedDateMillis = triggerAt)
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
                    triggerAt = zdt.toInstant().toEpochMilli()
                    showTimePicker = false
                }) { Text("SET") }
            },
            dismissButton = {
                TextButton(onClick = { showTimePicker = false }) { Text("CANCEL") }
            },
            text = { TimePicker(state = timeState) }
        )
    }

    if (showDeleteConfirm) {
        AlertDialog(
            onDismissRequest = { showDeleteConfirm = false },
            title = { Text("DELETE REMINDER?", style = MaterialTheme.typography.titleMedium) },
            text = { Text("\"${text.ifBlank { "This reminder" }}\" will be permanently deleted. This can't be undone.") },
            confirmButton = {
                TextButton(onClick = {
                    showDeleteConfirm = false
                    loadedReminder?.let { viewModel.delete(it) }
                    onDone()
                }) { Text("DELETE", color = PriorityUrgent) }
            },
            dismissButton = {
                TextButton(onClick = { showDeleteConfirm = false }) { Text("CANCEL") }
            }
        )
    }
}
