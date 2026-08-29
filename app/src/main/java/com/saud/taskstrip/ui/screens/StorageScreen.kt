package com.saud.taskstrip.ui.screens

import android.content.ActivityNotFoundException
import android.net.Uri
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.AddAPhoto
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.Label
import androidx.compose.material.icons.filled.PlayCircle
import androidx.compose.material.icons.filled.UploadFile
import androidx.compose.material.icons.filled.VideoLibrary
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.AssistChip
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
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
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.sp
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import coil.compose.AsyncImage
import com.saud.taskstrip.StorageViewModel
import com.saud.taskstrip.data.StorageItemEntity
import com.saud.taskstrip.data.StorageItemType
import com.saud.taskstrip.media.DOCUMENT_MIME_TYPES
import com.saud.taskstrip.media.DocumentOpener
import com.saud.taskstrip.media.VideoThumbnail
import com.saud.taskstrip.ui.components.ImageViewerDialog
import com.saud.taskstrip.ui.components.VideoViewerDialog
import com.saud.taskstrip.ui.theme.AmberTab
import com.saud.taskstrip.ui.theme.BayBackground
import com.saud.taskstrip.ui.theme.BaySurface
import com.saud.taskstrip.ui.theme.InkColor
import com.saud.taskstrip.ui.theme.Paper
import com.saud.taskstrip.ui.theme.PriorityUrgent
import java.io.File

// Quick-pick starting points for a document's tag/emoji — same idea as ReminderEditScreen's
// presets: one tap fills both fields, but any tag name and emoji can still be typed by hand.
val STORAGE_TAG_PRESETS = listOf(
    "Invoice" to "🧾",
    "Contract" to "✍️",
    "Receipt" to "💳",
    "Manual" to "📘",
    "ID" to "🪪",
    "Medical" to "💊",
    "Travel" to "✈️",
    "Warranty" to "🛡️"
)

// A shared library, separate from any one strip — files land here from another app's share
// sheet or a manual pick, and any strip can later duplicate one of these into its own
// attachments (see StoragePickerDialog). Deleting here never touches a strip that already took
// its own copy, and vice versa.
@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun StorageScreen(
    viewModel: StorageViewModel,
    onBack: () -> Unit
) {
    val context = LocalContext.current
    val items by viewModel.items.collectAsStateWithLifecycle()
    val images = remember(items) { items.filter { it.type == StorageItemType.IMAGE } }
    val videos = remember(items) { items.filter { it.type == StorageItemType.VIDEO } }
    val allDocuments = remember(items) { items.filter { it.type == StorageItemType.DOCUMENT } }

    var tagFilter by rememberSaveable { mutableStateOf<String?>(null) }
    var tagMenuExpanded by remember { mutableStateOf(false) }
    var tagEditTarget by remember { mutableStateOf<StorageItemEntity?>(null) }

    // Tag -> emoji for the filter menu's labels; the last document using a tag wins if two that
    // share a name were given different emoji (same rule RemindersScreen applies).
    val documentTagEmojis = remember(allDocuments) {
        allDocuments.filter { it.tag.isNotBlank() }.associate { it.tag to it.tagEmoji }
    }
    val availableTags = remember(documentTagEmojis) { documentTagEmojis.keys.sorted() }
    // A tag whose last document was deleted or retagged stops applying, rather than leaving the
    // list filtered down to nothing. Derived, not assigned back to tagFilter, so composition
    // never writes state it is also reading.
    val activeTag = tagFilter?.takeIf { it in availableTags }
    val documents = remember(allDocuments, activeTag) {
        activeTag?.let { t -> allDocuments.filter { it.tag == t } } ?: allDocuments
    }

    var imageViewerIndex by remember { mutableStateOf<Int?>(null) }
    var videoViewerPath by remember { mutableStateOf<String?>(null) }
    var pendingDelete by remember { mutableStateOf<StorageItemEntity?>(null) }

    val photoPicker = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.PickMultipleVisualMedia()
    ) { uris: List<Uri> ->
        uris.forEach { viewModel.addFromUri(it, context.contentResolver.getType(it), null) }
    }
    val videoPicker = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.PickMultipleVisualMedia()
    ) { uris: List<Uri> ->
        uris.forEach { viewModel.addFromUri(it, context.contentResolver.getType(it), null) }
    }
    val documentPicker = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.OpenMultipleDocuments()
    ) { uris: List<Uri> ->
        uris.forEach { viewModel.addFromUri(it, context.contentResolver.getType(it), null) }
    }

    Scaffold(
        containerColor = BayBackground,
        topBar = {
            TopAppBar(
                title = { Text("STORAGE", style = MaterialTheme.typography.titleLarge, color = Paper) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back", tint = Paper)
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = BayBackground)
            )
        }
    ) { padding ->
        Column(
            Modifier
                .padding(padding)
                .padding(16.dp)
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
        ) {
            Text(
                text = "Share a file to Task Strips from any app, or add one below — pick it from " +
                    "here later when a strip needs it.",
                style = MaterialTheme.typography.bodyMedium,
                color = Paper.copy(alpha = 0.6f)
            )
            Spacer(Modifier.height(20.dp))

            Text("PHOTOS", style = MaterialTheme.typography.labelSmall, color = Paper.copy(alpha = 0.7f))
            Spacer(Modifier.height(6.dp))
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                images.forEachIndexed { index, item ->
                    StorageTile(
                        onClick = { imageViewerIndex = index },
                        onRemove = { pendingDelete = item }
                    ) {
                        AsyncImage(
                            model = File(item.path),
                            contentDescription = item.name,
                            contentScale = ContentScale.Crop,
                            modifier = Modifier.size(72.dp).clip(RoundedCornerShape(4.dp))
                        )
                    }
                }
                Box(
                    Modifier
                        .size(72.dp)
                        .clip(RoundedCornerShape(4.dp))
                        .background(Paper.copy(alpha = 0.08f))
                        .clickable { photoPicker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) },
                    contentAlignment = Alignment.Center
                ) {
                    Icon(Icons.Default.AddAPhoto, contentDescription = "Add photo", tint = Paper.copy(alpha = 0.6f))
                }
            }

            Spacer(Modifier.height(20.dp))
            Text("VIDEOS", style = MaterialTheme.typography.labelSmall, color = Paper.copy(alpha = 0.7f))
            Spacer(Modifier.height(6.dp))
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                videos.forEach { item ->
                    val thumb = remember(item.path) { VideoThumbnail.getFrame(item.path)?.asImageBitmap() }
                    StorageTile(
                        onClick = { videoViewerPath = item.path },
                        onRemove = { pendingDelete = item }
                    ) {
                        Box(
                            Modifier.size(72.dp).clip(RoundedCornerShape(4.dp)).background(Paper.copy(alpha = 0.08f)),
                            contentAlignment = Alignment.Center
                        ) {
                            if (thumb != null) {
                                Image(bitmap = thumb, contentDescription = item.name, contentScale = ContentScale.Crop, modifier = Modifier.size(72.dp))
                            }
                            Icon(Icons.Default.PlayCircle, contentDescription = null, tint = Paper)
                        }
                    }
                }
                Box(
                    Modifier
                        .size(72.dp)
                        .clip(RoundedCornerShape(4.dp))
                        .background(Paper.copy(alpha = 0.08f))
                        .clickable { videoPicker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.VideoOnly)) },
                    contentAlignment = Alignment.Center
                ) {
                    Icon(Icons.Default.VideoLibrary, contentDescription = "Add video", tint = Paper.copy(alpha = 0.6f))
                }
            }

            Spacer(Modifier.height(20.dp))
            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
                Text("DOCUMENTS", style = MaterialTheme.typography.labelSmall, color = Paper.copy(alpha = 0.7f))
                if (activeTag != null) {
                    Spacer(Modifier.width(8.dp))
                    Text(
                        text = "${documentTagEmojis[activeTag].orEmpty()} ${activeTag.uppercase()}".trim(),
                        style = MaterialTheme.typography.labelSmall,
                        color = AmberTab
                    )
                }
                Spacer(Modifier.weight(1f))
                if (availableTags.isNotEmpty()) {
                    IconButton(onClick = { tagMenuExpanded = true }) {
                        Icon(
                            Icons.Default.Label,
                            contentDescription = "Filter documents by tag",
                            tint = if (activeTag != null) AmberTab else Paper
                        )
                    }
                    DropdownMenu(expanded = tagMenuExpanded, onDismissRequest = { tagMenuExpanded = false }) {
                        DropdownMenuItem(
                            text = { Text("ALL") },
                            trailingIcon = {
                                if (activeTag == null) Icon(Icons.Default.Check, contentDescription = null, tint = AmberTab)
                            },
                            onClick = {
                                tagFilter = null
                                tagMenuExpanded = false
                            }
                        )
                        availableTags.forEach { tag ->
                            DropdownMenuItem(
                                text = { Text("${documentTagEmojis[tag].orEmpty()} ${tag.uppercase()}".trim()) },
                                trailingIcon = {
                                    if (activeTag == tag) Icon(Icons.Default.Check, contentDescription = null, tint = AmberTab)
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
            Spacer(Modifier.height(6.dp))
            Column {
                documents.forEach { item ->
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable {
                                try {
                                    DocumentOpener.open(context, item.path)
                                } catch (e: ActivityNotFoundException) {
                                    Toast.makeText(context, "No app on this device can open that file", Toast.LENGTH_SHORT).show()
                                }
                            }
                            .padding(vertical = 6.dp)
                    ) {
                        if (item.tagEmoji.isNotBlank()) {
                            Text(text = item.tagEmoji, fontSize = 20.sp)
                        } else {
                            Icon(Icons.Default.Description, contentDescription = null, tint = AmberTab)
                        }
                        Spacer(Modifier.width(10.dp))
                        Column(Modifier.weight(1f)) {
                            Text(
                                text = item.name,
                                style = MaterialTheme.typography.bodyMedium,
                                color = Paper.copy(alpha = 0.8f),
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis
                            )
                            if (item.tag.isNotBlank()) {
                                Text(
                                    text = item.tag.uppercase(),
                                    style = MaterialTheme.typography.labelSmall,
                                    color = AmberTab
                                )
                            }
                        }
                        IconButton(onClick = { tagEditTarget = item }) {
                            Icon(
                                Icons.Default.Label,
                                contentDescription = "Tag ${item.name}",
                                tint = if (item.tag.isNotBlank()) AmberTab else Paper.copy(alpha = 0.6f)
                            )
                        }
                        IconButton(onClick = { pendingDelete = item }) {
                            Icon(Icons.Default.Delete, contentDescription = "Remove ${item.name}", tint = Paper.copy(alpha = 0.6f))
                        }
                    }
                }
                Spacer(Modifier.height(4.dp))
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier
                        .clickable { documentPicker.launch(DOCUMENT_MIME_TYPES) }
                        .padding(vertical = 6.dp)
                ) {
                    Icon(Icons.Default.UploadFile, contentDescription = null, tint = Paper.copy(alpha = 0.7f))
                    Spacer(Modifier.width(8.dp))
                    Text(
                        text = if (allDocuments.isEmpty()) "ADD DOCUMENT" else "ADD ANOTHER DOCUMENT",
                        style = MaterialTheme.typography.bodyMedium,
                        color = Paper.copy(alpha = 0.7f)
                    )
                }
            }
        }
    }

    val openIndex = imageViewerIndex
    if (openIndex != null) {
        ImageViewerDialog(
            images = images.map { it.path },
            startIndex = openIndex,
            onDismiss = { imageViewerIndex = null },
            onDelete = { path ->
                images.firstOrNull { it.path == path }?.let { viewModel.delete(it) }
                imageViewerIndex = null
            }
        )
    }

    val openVideoPath = videoViewerPath
    if (openVideoPath != null) {
        VideoViewerDialog(
            path = openVideoPath,
            onDismiss = { videoViewerPath = null },
            onDelete = {
                videos.firstOrNull { it.path == openVideoPath }?.let { viewModel.delete(it) }
                videoViewerPath = null
            }
        )
    }

    tagEditTarget?.let { item ->
        StorageTagDialog(
            item = item,
            onDismiss = { tagEditTarget = null },
            onSave = { tag, emoji ->
                viewModel.setTag(item, tag, emoji)
                tagEditTarget = null
            }
        )
    }

    pendingDelete?.let { item ->
        AlertDialog(
            onDismissRequest = { pendingDelete = null },
            title = { Text("DELETE FROM STORAGE?", style = MaterialTheme.typography.titleMedium) },
            text = { Text("\"${item.name}\" will be permanently deleted. Strips that already took a copy of it keep theirs.") },
            confirmButton = {
                TextButton(onClick = {
                    viewModel.delete(item)
                    pendingDelete = null
                }) { Text("DELETE", color = PriorityUrgent) }
            },
            dismissButton = {
                TextButton(onClick = { pendingDelete = null }) { Text("CANCEL") }
            }
        )
    }
}

/** Assigns a document's tag and emoji. Clearing both fields (or CLEAR) makes it untagged again,
 * which also drops the tag from the filter menu once no document still uses it. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun StorageTagDialog(
    item: StorageItemEntity,
    onDismiss: () -> Unit,
    onSave: (String, String) -> Unit
) {
    var tag by rememberSaveable(item.id) { mutableStateOf(item.tag) }
    var emoji by rememberSaveable(item.id) { mutableStateOf(item.tagEmoji) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("TAG DOCUMENT", style = MaterialTheme.typography.titleMedium) },
        text = {
            Column {
                Text(
                    text = item.name,
                    style = MaterialTheme.typography.bodySmall,
                    color = Paper.copy(alpha = 0.6f),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                Spacer(Modifier.height(12.dp))
                Row(verticalAlignment = Alignment.Top) {
                    OutlinedTextField(
                        value = tag,
                        onValueChange = { tag = it },
                        label = { Text("TAG") },
                        singleLine = true,
                        textStyle = LocalTextStyle.current.copy(fontFamily = FontFamily.Monospace),
                        modifier = Modifier.weight(1f)
                    )
                    Spacer(Modifier.width(10.dp))
                    OutlinedTextField(
                        value = emoji,
                        onValueChange = { emoji = it.take(4) },
                        label = { Text("EMOJI") },
                        singleLine = true,
                        textStyle = LocalTextStyle.current.copy(fontFamily = FontFamily.Monospace),
                        modifier = Modifier.width(96.dp)
                    )
                }
                Spacer(Modifier.height(8.dp))
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    STORAGE_TAG_PRESETS.forEach { (presetTag, presetEmoji) ->
                        AssistChip(
                            onClick = { tag = presetTag; emoji = presetEmoji },
                            label = { Text("$presetEmoji $presetTag") }
                        )
                    }
                }
            }
        },
        confirmButton = {
            TextButton(onClick = { onSave(tag, emoji) }) { Text("SAVE", color = AmberTab) }
        },
        dismissButton = {
            Row {
                if (item.tag.isNotBlank() || item.tagEmoji.isNotBlank()) {
                    TextButton(onClick = { onSave("", "") }) { Text("CLEAR", color = PriorityUrgent) }
                }
                TextButton(onClick = onDismiss) { Text("CANCEL") }
            }
        }
    )
}

@Composable
private fun StorageTile(
    onClick: () -> Unit,
    onRemove: () -> Unit,
    content: @Composable () -> Unit
) {
    Box(Modifier.size(72.dp)) {
        Box(Modifier.size(72.dp).clip(RoundedCornerShape(4.dp)).clickable(onClick = onClick)) {
            content()
        }
        IconButton(
            onClick = onRemove,
            modifier = Modifier
                .align(Alignment.TopEnd)
                .size(22.dp)
                .background(InkColor.copy(alpha = 0.7f), CircleShape)
        ) {
            Icon(Icons.Default.Close, contentDescription = "Remove", tint = Paper, modifier = Modifier.size(14.dp))
        }
    }
}
