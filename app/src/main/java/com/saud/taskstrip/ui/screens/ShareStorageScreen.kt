package com.saud.taskstrip.ui.screens

import android.net.Uri
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
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
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.Image
import androidx.compose.material.icons.filled.Videocam
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LocalTextStyle
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.saud.taskstrip.StorageViewModel
import com.saud.taskstrip.media.MediaStorage
import com.saud.taskstrip.ui.theme.AmberTab
import com.saud.taskstrip.ui.theme.BayBackground
import com.saud.taskstrip.ui.theme.BaySurface
import com.saud.taskstrip.ui.theme.InkColor
import com.saud.taskstrip.ui.theme.Paper
import kotlinx.coroutines.launch

/** Shown when a photo/video/document is shared into Task Strips from another app, instead of
 * silently filing it away — lets the user confirm the save and optionally tag it right there, the
 * same tag a document can get later from the Storage screen, rather than only after digging it up
 * post-hoc. Cancelling leaves nothing behind since nothing is copied until SAVE is tapped. */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun ShareStorageScreen(
    uris: List<Uri>,
    storageViewModel: StorageViewModel,
    onDone: () -> Unit,
    onCancel: () -> Unit
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var tag by remember { mutableStateOf("") }
    var emoji by remember { mutableStateOf("") }
    var isSaving by remember { mutableStateOf(false) }

    val names = remember(uris) {
        uris.map { uri -> MediaStorage.queryDisplayName(context, uri) ?: "Shared file" }
    }
    val mimeTypes = remember(uris) {
        uris.map { uri -> context.contentResolver.getType(uri) }
    }

    fun save() {
        if (isSaving) return
        isSaving = true
        scope.launch {
            uris.forEachIndexed { index, uri ->
                storageViewModel.saveFromUri(
                    uri = uri,
                    mimeType = mimeTypes[index],
                    displayName = names[index],
                    tag = tag,
                    tagEmoji = emoji
                )
            }
            isSaving = false
            onDone()
        }
    }

    Scaffold(
        containerColor = BayBackground,
        topBar = {
            TopAppBar(
                title = { Text("SAVE TO STORAGE", style = MaterialTheme.typography.titleLarge, color = Paper) },
                navigationIcon = {
                    IconButton(onClick = onCancel) {
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
            Spacer(Modifier.height(4.dp))
            Text(
                text = if (uris.size == 1) "1 file shared from another app" else "${uris.size} files shared from another app",
                style = MaterialTheme.typography.bodyMedium,
                color = Paper.copy(alpha = 0.6f)
            )
            Spacer(Modifier.height(14.dp))

            LazyColumn(modifier = Modifier.weight(1f, fill = false)) {
                items(names.indices.toList()) { index ->
                    Surface(color = BaySurface, shape = RoundedCornerShape(4.dp), modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(12.dp)) {
                            val mime = mimeTypes[index].orEmpty()
                            Icon(
                                imageVector = when {
                                    mime.startsWith("image/") -> Icons.Default.Image
                                    mime.startsWith("video/") -> Icons.Default.Videocam
                                    else -> Icons.Default.Description
                                },
                                contentDescription = null,
                                tint = AmberTab
                            )
                            Spacer(Modifier.width(10.dp))
                            Text(
                                text = names[index],
                                style = MaterialTheme.typography.bodyMedium,
                                color = Paper.copy(alpha = 0.85f),
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis
                            )
                        }
                    }
                }
            }

            Spacer(Modifier.height(18.dp))
            Text("TAG (optional)", style = MaterialTheme.typography.labelSmall, color = Paper.copy(alpha = 0.7f))
            Spacer(Modifier.height(6.dp))
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

            Spacer(Modifier.height(18.dp))
            Button(
                onClick = { save() },
                enabled = !isSaving,
                colors = ButtonDefaults.buttonColors(containerColor = AmberTab, contentColor = InkColor),
                modifier = Modifier.fillMaxWidth().height(52.dp)
            ) {
                if (isSaving) {
                    CircularProgressIndicator(modifier = Modifier.height(20.dp), color = InkColor, strokeWidth = 2.dp)
                } else {
                    Text(
                        text = if (uris.size == 1) "SAVE TO STORAGE" else "SAVE ${uris.size} TO STORAGE",
                        style = MaterialTheme.typography.titleMedium,
                        color = InkColor
                    )
                }
            }
            Spacer(Modifier.height(12.dp))
        }
    }
}
