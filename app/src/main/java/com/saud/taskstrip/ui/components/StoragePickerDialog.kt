package com.saud.taskstrip.ui.components

import androidx.compose.foundation.Image
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
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.PlayCircle
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import coil.compose.AsyncImage
import com.saud.taskstrip.data.StorageItemEntity
import com.saud.taskstrip.data.StorageItemType
import com.saud.taskstrip.media.VideoThumbnail
import com.saud.taskstrip.ui.theme.AmberTab
import com.saud.taskstrip.ui.theme.BayBackground
import com.saud.taskstrip.ui.theme.BaySurface
import com.saud.taskstrip.ui.theme.InkColor
import com.saud.taskstrip.ui.theme.Paper
import java.io.File

/** Lets a strip pull one or more items already sitting in the shared library into its own
 * attachments — the picked items are duplicated (see MediaStorage.duplicate*), never moved, so
 * the library keeps its own independent copy. */
@Composable
fun StoragePickerDialog(
    items: List<StorageItemEntity>,
    typeFilter: String,
    onDismiss: () -> Unit,
    onConfirm: (List<StorageItemEntity>) -> Unit
) {
    val filtered = remember(items, typeFilter) { items.filter { it.type == typeFilter } }
    var selected by remember { mutableStateOf(setOf<Long>()) }

    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Column(
            Modifier
                .fillMaxSize()
                .background(BayBackground)
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.fillMaxWidth().padding(12.dp)
            ) {
                IconButton(onClick = onDismiss) {
                    Icon(Icons.Default.Close, contentDescription = "Cancel", tint = Paper)
                }
                Text(
                    text = "ADD FROM STORAGE",
                    style = MaterialTheme.typography.titleMedium,
                    color = Paper,
                    modifier = Modifier.weight(1f)
                )
            }
            if (filtered.isEmpty()) {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Text(
                        text = "NOTHING IN STORAGE YET",
                        style = MaterialTheme.typography.bodyMedium,
                        color = Paper.copy(alpha = 0.5f)
                    )
                }
            } else {
                LazyColumn(Modifier.weight(1f).padding(horizontal = 12.dp)) {
                    items(filtered, key = { it.id }) { item ->
                        val isSelected = item.id in selected
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(vertical = 4.dp)
                                .background(BaySurface, RoundedCornerShape(4.dp))
                                .clickable {
                                    selected = if (isSelected) selected - item.id else selected + item.id
                                }
                                .padding(8.dp)
                        ) {
                            StorageThumb(item)
                            Spacer(Modifier.width(10.dp))
                            Text(
                                text = item.name,
                                style = MaterialTheme.typography.bodyMedium,
                                color = Paper.copy(alpha = 0.85f),
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                                modifier = Modifier.weight(1f)
                            )
                            Box(
                                Modifier
                                    .size(24.dp)
                                    .clip(RoundedCornerShape(50))
                                    .background(if (isSelected) AmberTab else Paper.copy(alpha = 0.12f)),
                                contentAlignment = Alignment.Center
                            ) {
                                if (isSelected) {
                                    Icon(Icons.Default.Check, contentDescription = null, tint = InkColor, modifier = Modifier.size(16.dp))
                                }
                            }
                        }
                    }
                }
                Button(
                    onClick = { onConfirm(filtered.filter { it.id in selected }) },
                    enabled = selected.isNotEmpty(),
                    colors = ButtonDefaults.buttonColors(containerColor = AmberTab, contentColor = InkColor),
                    modifier = Modifier.fillMaxWidth().padding(12.dp).height(48.dp)
                ) {
                    Text("ADD ${selected.size}".trim(), style = MaterialTheme.typography.bodyLarge)
                }
            }
        }
    }
}

@Composable
private fun StorageThumb(item: StorageItemEntity) {
    when (item.type) {
        StorageItemType.IMAGE -> AsyncImage(
            model = File(item.path),
            contentDescription = null,
            contentScale = ContentScale.Crop,
            modifier = Modifier.size(44.dp).clip(RoundedCornerShape(4.dp))
        )
        StorageItemType.VIDEO -> {
            val thumb = remember(item.path) { VideoThumbnail.getFrame(item.path)?.asImageBitmap() }
            Box(
                Modifier.size(44.dp).clip(RoundedCornerShape(4.dp)).background(Paper.copy(alpha = 0.08f)),
                contentAlignment = Alignment.Center
            ) {
                if (thumb != null) {
                    Image(bitmap = thumb, contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.size(44.dp))
                }
                Icon(Icons.Default.PlayCircle, contentDescription = null, tint = Paper, modifier = Modifier.size(18.dp))
            }
        }
        else -> Box(
            Modifier.size(44.dp).clip(RoundedCornerShape(4.dp)).background(Paper.copy(alpha = 0.08f)),
            contentAlignment = Alignment.Center
        ) {
            Icon(Icons.Default.Description, contentDescription = null, tint = AmberTab, modifier = Modifier.size(20.dp))
        }
    }
}
