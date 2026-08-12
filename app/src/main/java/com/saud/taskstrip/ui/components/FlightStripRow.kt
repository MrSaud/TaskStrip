package com.saud.taskstrip.ui.components

import android.widget.Toast
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.VolumeUp
import androidx.compose.material.icons.filled.Alarm
import androidx.compose.material.icons.filled.Block
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.HourglassTop
import androidx.compose.material.icons.filled.Image
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Replay
import androidx.compose.material.icons.filled.Repeat
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material.icons.filled.VideoLibrary
import androidx.compose.material.icons.filled.VolumeUp
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.saud.taskstrip.data.TaskEntity
import com.saud.taskstrip.media.TextToSpeechHelper
import com.saud.taskstrip.media.VoicePlayer
import com.saud.taskstrip.ui.theme.AmberTab
import com.saud.taskstrip.ui.theme.InkColor
import com.saud.taskstrip.ui.theme.Paper
import com.saud.taskstrip.ui.theme.PaperFaded
import com.saud.taskstrip.ui.theme.PriorityNormal
import com.saud.taskstrip.ui.theme.PriorityUrgent
import com.saud.taskstrip.ui.theme.tabColor
import java.util.concurrent.TimeUnit

val StripHeight = 104.dp
val StripShape = RoundedCornerShape(4.dp)

private val DUE_SOON_WINDOW_MILLIS = TimeUnit.DAYS.toMillis(2)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FlightStripRow(
    task: TaskEntity,
    completed: Boolean,
    onClick: () -> Unit,
    onDelete: () -> Unit,
    modifier: Modifier = Modifier,
    onToggleDone: (() -> Unit)? = null,
    dragModifier: Modifier? = null,
    trailingActions: @Composable () -> Unit = {},
    blockerTask: TaskEntity? = null
) {
    val context = LocalContext.current
    var showDeleteConfirm by remember { mutableStateOf(false) }

    val isBlocked = blockerTask != null && !blockerTask.isDone
    fun requestToggleDone() {
        if (isBlocked) {
            Toast.makeText(context, "Blocked by \"${blockerTask?.title}\"", Toast.LENGTH_SHORT).show()
        } else {
            onToggleDone?.invoke()
        }
    }

    val dismissState = rememberSwipeToDismissBoxState(
        confirmValueChange = { value ->
            when (value) {
                SwipeToDismissBoxValue.EndToStart -> {
                    // Delete is irreversible — ask first, and spring the row back to rest while
                    // we wait rather than leaving it hanging in the dismissed position.
                    showDeleteConfirm = true
                    false
                }
                SwipeToDismissBoxValue.StartToEnd -> {
                    // Fire the toggle but report "not confirmed" so the box springs back to rest
                    // instead of staying in the dismissed position — the row leaving this list
                    // (active <-> completed) happens naturally once the data changes.
                    requestToggleDone()
                    false
                }
                SwipeToDismissBoxValue.Settled -> false
            }
        }
    )

    val dueAt = task.dueAt
    val isOverdue = !completed && dueAt != null && dueAt <= System.currentTimeMillis()
    val dueColor = when {
        dueAt == null -> InkColor
        dueAt - System.currentTimeMillis() <= DUE_SOON_WINDOW_MILLIS -> PriorityUrgent
        else -> AmberTab
    }
    val player = remember { VoicePlayer() }
    var isPlayingAll by remember { mutableStateOf(false) }
    var playIndex by remember { mutableIntStateOf(0) }
    var showPlayConfirm by remember { mutableStateOf(false) }

    fun playFrom(index: Int) {
        if (index >= task.voiceNotes.size) {
            isPlayingAll = false
            return
        }
        playIndex = index
        isPlayingAll = true
        player.play(task.voiceNotes[index]) { playFrom(index + 1) }
    }

    DisposableEffect(task.id) {
        onDispose { player.stop() }
    }

    // Overdue, not-done strips get a pulsing alarm icon (alpha + scale breathing) next to the
    // DUE field to keep drawing the eye back to them — no more full-border flashing.
    val pulseAlpha = if (isOverdue) {
        val transition = rememberInfiniteTransition(label = "overduePulse")
        val alpha by transition.animateFloat(
            initialValue = 0.35f,
            targetValue = 1f,
            animationSpec = infiniteRepeatable(tween(700, easing = LinearEasing), RepeatMode.Reverse),
            label = "pulseAlpha"
        )
        alpha
    } else {
        0f
    }

    SwipeToDismissBox(
        state = dismissState,
        modifier = modifier,
        enableDismissFromStartToEnd = onToggleDone != null,
        backgroundContent = {
            val isToggleSwipe = dismissState.dismissDirection == SwipeToDismissBoxValue.StartToEnd
            Box(
                Modifier
                    .fillMaxSize()
                    .padding(horizontal = 10.dp, vertical = 4.dp)
                    .clip(StripShape)
                    .background(if (isToggleSwipe) PriorityNormal else PriorityUrgent),
                contentAlignment = if (isToggleSwipe) Alignment.CenterStart else Alignment.CenterEnd
            ) {
                Icon(
                    imageVector = if (isToggleSwipe) {
                        if (completed) Icons.Default.Replay else Icons.Default.Check
                    } else {
                        Icons.Default.Delete
                    },
                    contentDescription = if (isToggleSwipe) {
                        if (completed) "Mark active" else "Mark complete"
                    } else {
                        "Delete"
                    },
                    tint = Paper,
                    modifier = Modifier.padding(horizontal = 24.dp)
                )
            }
        }
    ) {
        Surface(
            modifier = Modifier
                .fillMaxWidth()
                .height(StripHeight)
                .padding(horizontal = 10.dp, vertical = 4.dp)
                .clip(StripShape),
            color = if (completed) PaperFaded else Paper,
            shadowElevation = if (completed) 0.dp else 3.dp
        ) {
            Box(Modifier.fillMaxSize()) {
            Column(Modifier.fillMaxSize()) {
                Row(Modifier.weight(1f)) {
                    // Tab + content together form the draggable/tappable body: the whole strip,
                    // not just a thin handle, responds to long-press-drag for reordering.
                    Row(
                        modifier = Modifier
                            .weight(1f)
                            .fillMaxHeight()
                            .clickable(onClick = onClick)
                            .then(dragModifier ?: Modifier)
                    ) {
                        Box(
                            Modifier
                                .width(10.dp)
                                .fillMaxHeight()
                                .background(task.priority.tabColor())
                        )
                        Column(
                            Modifier
                                .weight(1f)
                                .padding(horizontal = 12.dp, vertical = 8.dp)
                        ) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Text(
                                    text = task.title.uppercase(),
                                    style = MaterialTheme.typography.titleMedium,
                                    color = InkColor,
                                    textDecoration = if (completed) TextDecoration.LineThrough else null,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis,
                                    modifier = Modifier.weight(1f)
                                )
                                Spacer(Modifier.width(8.dp))
                                Text(
                                    text = "FILED ${formatTimestampShort(task.createdAt)}",
                                    style = MaterialTheme.typography.labelSmall,
                                    color = InkColor.copy(alpha = 0.45f),
                                    maxLines = 1
                                )
                                if (task.repeatIntervalDays != null) {
                                    Spacer(Modifier.width(8.dp))
                                    Icon(
                                        Icons.Default.Repeat,
                                        contentDescription = "Repeats every ${task.repeatIntervalDays} days",
                                        tint = InkColor.copy(alpha = 0.45f),
                                        modifier = Modifier.height(14.dp)
                                    )
                                }
                                Spacer(Modifier.width(8.dp))
                                Text(
                                    text = task.priority.label,
                                    style = MaterialTheme.typography.labelSmall,
                                    color = task.priority.tabColor(),
                                    fontWeight = FontWeight.Bold
                                )
                            }
                            Spacer(Modifier.height(4.dp))
                            HorizontalDivider(color = InkColor.copy(alpha = 0.15f))
                            Spacer(Modifier.height(4.dp))
                            Row(
                                Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    if (task.tags.isNotEmpty()) {
                                        StripField(label = "TAGS", value = task.tags.joinToString(", ") { it.uppercase() })
                                        Spacer(Modifier.width(14.dp))
                                    }
                                    if (dueAt != null) {
                                        StripField(label = "DUE", value = formatEtaShort(dueAt), valueColor = dueColor)
                                    }
                                    if (isOverdue) {
                                        Spacer(Modifier.width(6.dp))
                                        Icon(
                                            Icons.Default.Alarm,
                                            contentDescription = "Overdue",
                                            tint = PriorityUrgent.copy(alpha = pulseAlpha),
                                            modifier = Modifier
                                                .height(18.dp)
                                                .scale(0.85f + pulseAlpha * 0.3f)
                                        )
                                    }
                                }
                                if (task.images.isNotEmpty() || task.voiceNotes.isNotEmpty() || task.documents.isNotEmpty() || task.videos.isNotEmpty() || task.contacts.isNotEmpty()) {
                                    Row(verticalAlignment = Alignment.CenterVertically) {
                                        if (task.images.isNotEmpty()) {
                                            Icon(
                                                Icons.Default.Image,
                                                contentDescription = "${task.images.size} photos attached",
                                                tint = InkColor.copy(alpha = 0.45f),
                                                modifier = Modifier.height(14.dp)
                                            )
                                            Text(
                                                text = "${task.images.size}",
                                                style = MaterialTheme.typography.labelSmall,
                                                color = InkColor.copy(alpha = 0.45f)
                                            )
                                            Spacer(Modifier.width(8.dp))
                                        }
                                        if (task.documents.isNotEmpty()) {
                                            Icon(
                                                Icons.Default.Description,
                                                contentDescription = "${task.documents.size} documents attached",
                                                tint = InkColor.copy(alpha = 0.45f),
                                                modifier = Modifier.height(14.dp)
                                            )
                                            Text(
                                                text = "${task.documents.size}",
                                                style = MaterialTheme.typography.labelSmall,
                                                color = InkColor.copy(alpha = 0.45f)
                                            )
                                            Spacer(Modifier.width(8.dp))
                                        }
                                        if (task.videos.isNotEmpty()) {
                                            Icon(
                                                Icons.Default.VideoLibrary,
                                                contentDescription = "${task.videos.size} videos attached",
                                                tint = InkColor.copy(alpha = 0.45f),
                                                modifier = Modifier.height(14.dp)
                                            )
                                            Text(
                                                text = "${task.videos.size}",
                                                style = MaterialTheme.typography.labelSmall,
                                                color = InkColor.copy(alpha = 0.45f)
                                            )
                                            Spacer(Modifier.width(8.dp))
                                        }
                                        if (task.contacts.isNotEmpty()) {
                                            Icon(
                                                Icons.Default.Person,
                                                contentDescription = "${task.contacts.size} contacts attached",
                                                tint = InkColor.copy(alpha = 0.45f),
                                                modifier = Modifier.height(14.dp)
                                            )
                                            Text(
                                                text = "${task.contacts.size}",
                                                style = MaterialTheme.typography.labelSmall,
                                                color = InkColor.copy(alpha = 0.45f)
                                            )
                                            Spacer(Modifier.width(8.dp))
                                        }
                                        if (task.voiceNotes.isNotEmpty()) {
                                            Row(
                                                verticalAlignment = Alignment.CenterVertically,
                                                modifier = Modifier.clickable {
                                                    if (isPlayingAll) {
                                                        player.stop()
                                                        isPlayingAll = false
                                                    } else {
                                                        showPlayConfirm = true
                                                    }
                                                }
                                            ) {
                                                Icon(
                                                    imageVector = if (isPlayingAll) Icons.Default.Stop else Icons.Default.Mic,
                                                    contentDescription = if (isPlayingAll) {
                                                        "Stop playing voice notes"
                                                    } else {
                                                        "Play ${task.voiceNotes.size} voice notes"
                                                    },
                                                    tint = if (isPlayingAll) AmberTab else InkColor.copy(alpha = 0.45f),
                                                    modifier = Modifier.height(14.dp)
                                                )
                                                Text(
                                                    text = if (isPlayingAll) "${playIndex + 1}/${task.voiceNotes.size}" else "${task.voiceNotes.size}",
                                                    style = MaterialTheme.typography.labelSmall,
                                                    color = if (isPlayingAll) AmberTab else InkColor.copy(alpha = 0.45f)
                                                )
                                            }
                                        }
                                    }
                                }
                            }
                            if (isBlocked || (task.waitingOnName.isNotBlank() && !completed)) {
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    if (isBlocked) {
                                        Icon(
                                            Icons.Default.Block,
                                            contentDescription = null,
                                            tint = PriorityUrgent,
                                            modifier = Modifier.height(13.dp)
                                        )
                                        Spacer(Modifier.width(3.dp))
                                        Text(
                                            text = "BLOCKED BY ${blockerTask?.title?.uppercase()}",
                                            style = MaterialTheme.typography.labelSmall,
                                            color = PriorityUrgent,
                                            maxLines = 1,
                                            overflow = TextOverflow.Ellipsis
                                        )
                                    }
                                    if (isBlocked && task.waitingOnName.isNotBlank() && !completed) {
                                        Spacer(Modifier.width(10.dp))
                                    }
                                    if (task.waitingOnName.isNotBlank() && !completed) {
                                        Icon(
                                            Icons.Default.HourglassTop,
                                            contentDescription = null,
                                            tint = AmberTab,
                                            modifier = Modifier.height(13.dp)
                                        )
                                        Spacer(Modifier.width(3.dp))
                                        Text(
                                            text = "WAITING ON ${task.waitingOnName.uppercase()}",
                                            style = MaterialTheme.typography.labelSmall,
                                            color = InkColor.copy(alpha = 0.6f),
                                            maxLines = 1,
                                            overflow = TextOverflow.Ellipsis
                                        )
                                    }
                                }
                            }
                            if (task.notes.isNotBlank()) {
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    Icon(
                                        Icons.AutoMirrored.Filled.VolumeUp,
                                        contentDescription = "Read notes aloud",
                                        tint = InkColor.copy(alpha = 0.5f),
                                        modifier = Modifier
                                            .height(14.dp)
                                            .clickable { TextToSpeechHelper.speak(context, task.notes) }
                                    )
                                    Spacer(Modifier.width(4.dp))
                                    Text(
                                        text = task.notes,
                                        style = MaterialTheme.typography.bodyMedium,
                                        color = InkColor.copy(alpha = 0.6f),
                                        maxLines = 1,
                                        overflow = TextOverflow.Ellipsis,
                                        modifier = Modifier.weight(1f)
                                    )
                                }
                            }
                        }
                    }
                    trailingActions()
                }
                ProgressTrack(progress = task.progress, color = task.priority.tabColor())
            }
            if (task.progress > 0) {
                Text(
                    text = "${task.progress}%",
                    style = MaterialTheme.typography.labelSmall,
                    color = task.priority.tabColor(),
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier
                        .align(Alignment.BottomEnd)
                        .padding(end = 6.dp, bottom = 7.dp)
                )
            }
            }
        }
    }

    if (showDeleteConfirm) {
        AlertDialog(
            onDismissRequest = { showDeleteConfirm = false },
            title = { Text("DELETE STRIP?", style = MaterialTheme.typography.titleMedium) },
            text = { Text("\"${task.title}\" and its attachments will be permanently deleted. This can't be undone.") },
            confirmButton = {
                TextButton(onClick = {
                    showDeleteConfirm = false
                    onDelete()
                }) { Text("DELETE", color = PriorityUrgent) }
            },
            dismissButton = {
                TextButton(onClick = { showDeleteConfirm = false }) { Text("CANCEL") }
            }
        )
    }

    if (showPlayConfirm) {
        AlertDialog(
            onDismissRequest = { showPlayConfirm = false },
            title = { Text("PLAY VOICE NOTES?", style = MaterialTheme.typography.titleMedium) },
            text = {
                Text(
                    if (task.voiceNotes.size == 1) {
                        "Play the voice note attached to \"${task.title}\"?"
                    } else {
                        "Play all ${task.voiceNotes.size} voice notes attached to \"${task.title}\"?"
                    }
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    showPlayConfirm = false
                    playFrom(0)
                }) { Text("PLAY") }
            },
            dismissButton = {
                TextButton(onClick = { showPlayConfirm = false }) { Text("CANCEL") }
            }
        )
    }
}

@Composable
private fun ProgressTrack(progress: Int, color: Color) {
    Box(
        Modifier
            .fillMaxWidth()
            .height(4.dp)
            .background(InkColor.copy(alpha = 0.1f))
    ) {
        Box(
            Modifier
                .fillMaxHeight()
                .fillMaxWidth(fraction = (progress.coerceIn(0, 100)) / 100f)
                .background(color)
        )
    }
}

@Composable
private fun StripField(label: String, value: String, valueColor: Color = InkColor) {
    Column {
        Text(text = label, style = MaterialTheme.typography.labelSmall, color = InkColor.copy(alpha = 0.5f))
        Text(text = value, style = MaterialTheme.typography.bodyMedium, color = valueColor, fontWeight = FontWeight.SemiBold)
    }
}
