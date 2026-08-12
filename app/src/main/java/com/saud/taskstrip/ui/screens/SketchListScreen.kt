package com.saud.taskstrip.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Draw
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExtendedFloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import coil.compose.AsyncImage
import com.saud.taskstrip.media.SketchStorage
import com.saud.taskstrip.ui.theme.AmberTab
import com.saud.taskstrip.ui.theme.BayBackground
import com.saud.taskstrip.ui.theme.InkColor
import com.saud.taskstrip.ui.theme.Paper
import java.io.File

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SketchListScreen(
    onBack: () -> Unit,
    onOpenSketch: (String?) -> Unit
) {
    val context = LocalContext.current
    var notes by remember { mutableStateOf(SketchStorage.listNotes(context)) }
    var renameTarget by remember { mutableStateOf<File?>(null) }

    fun refresh() {
        notes = SketchStorage.listNotes(context)
    }

    // Compose Navigation keeps this screen's composition alive on the back stack, so a plain
    // LaunchedEffect(Unit) would only fire once and never see edits made after returning from the
    // canvas — refresh on every ON_RESUME instead, which fires each time this screen comes back
    // into view.
    val lifecycleOwner = LocalLifecycleOwner.current
    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) refresh()
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    Scaffold(
        containerColor = BayBackground,
        topBar = {
            TopAppBar(
                title = { Text("SKETCH NOTES", style = MaterialTheme.typography.titleLarge, color = Paper) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back", tint = Paper)
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = BayBackground)
            )
        },
        floatingActionButton = {
            ExtendedFloatingActionButton(
                onClick = { onOpenSketch(null) },
                containerColor = AmberTab,
                contentColor = InkColor,
                icon = { Icon(Icons.Default.Add, contentDescription = null) },
                text = { Text("NEW SKETCH", style = MaterialTheme.typography.bodyLarge) }
            )
        }
    ) { padding ->
        if (notes.isEmpty()) {
            Box(Modifier.padding(padding).fillMaxSize(), contentAlignment = Alignment.Center) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Icon(Icons.Default.Draw, contentDescription = null, tint = Paper.copy(alpha = 0.3f))
                    Text(
                        text = "NO SKETCHES YET",
                        style = MaterialTheme.typography.titleMedium,
                        color = Paper.copy(alpha = 0.5f)
                    )
                    Text(
                        text = "Tap NEW SKETCH to draw or write freely",
                        style = MaterialTheme.typography.bodyMedium,
                        color = Paper.copy(alpha = 0.35f)
                    )
                }
            }
        } else {
            LazyVerticalGrid(
                columns = GridCells.Fixed(2),
                contentPadding = padding,
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
                modifier = Modifier.padding(horizontal = 16.dp)
            ) {
                items(notes, key = { it.absolutePath }) { note ->
                    SketchTile(
                        note = note,
                        onClick = { onOpenSketch(note.name) },
                        onRename = { renameTarget = note },
                        onDelete = {
                            SketchStorage.deleteNote(note)
                            refresh()
                        }
                    )
                }
            }
        }
    }

    renameTarget?.let { note ->
        var nameInput by remember(note) { mutableStateOf(SketchStorage.getName(note) ?: "") }
        AlertDialog(
            onDismissRequest = { renameTarget = null },
            title = { Text("RENAME SKETCH", style = MaterialTheme.typography.titleMedium) },
            text = {
                OutlinedTextField(
                    value = nameInput,
                    onValueChange = { nameInput = it },
                    label = { Text("Name") },
                    placeholder = { Text(SketchStorage.dateLabel(note)) },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    SketchStorage.setName(note, nameInput)
                    renameTarget = null
                    refresh()
                }) { Text("SAVE") }
            },
            dismissButton = {
                TextButton(onClick = { renameTarget = null }) { Text("CANCEL") }
            }
        )
    }
}

@Composable
private fun SketchTile(note: File, onClick: () -> Unit, onRename: () -> Unit, onDelete: () -> Unit) {
    // Not `remember`-cached: File.equals() only compares paths, so a rename or a newly drawn
    // page (same path, changed content on disk) wouldn't invalidate a cached value — these are
    // cheap local reads anyway, so just re-read them fresh every recomposition.
    val pages = SketchStorage.listPages(note)
    val name = SketchStorage.getName(note)
    Column {
        Box(
            Modifier
                .fillMaxWidth()
                .aspectRatio(1f)
                .clip(RoundedCornerShape(6.dp))
                .background(Paper)
                .clickable(onClick = onClick)
        ) {
            AsyncImage(
                model = pages.firstOrNull(),
                contentDescription = name ?: "Sketch from ${SketchStorage.dateLabel(note)}",
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize()
            )
            if (pages.size > 1) {
                Text(
                    text = "${pages.size} PAGES",
                    style = MaterialTheme.typography.labelSmall,
                    color = Paper,
                    modifier = Modifier
                        .align(Alignment.BottomStart)
                        .padding(6.dp)
                        .clip(RoundedCornerShape(4.dp))
                        .background(InkColor.copy(alpha = 0.6f))
                        .padding(horizontal = 6.dp, vertical = 2.dp)
                )
            }
            Row(modifier = Modifier.align(Alignment.TopEnd).padding(4.dp)) {
                IconButton(onClick = onRename) {
                    Icon(
                        Icons.Default.Edit,
                        contentDescription = "Rename sketch",
                        tint = Paper,
                        modifier = Modifier
                            .clip(RoundedCornerShape(4.dp))
                            .background(InkColor.copy(alpha = 0.55f))
                            .padding(4.dp)
                    )
                }
                Spacer(Modifier.width(4.dp))
                IconButton(onClick = onDelete) {
                    Icon(
                        Icons.Default.Delete,
                        contentDescription = "Delete sketch",
                        tint = Paper,
                        modifier = Modifier
                            .clip(RoundedCornerShape(4.dp))
                            .background(InkColor.copy(alpha = 0.55f))
                            .padding(4.dp)
                    )
                }
            }
        }
        Text(
            text = name ?: "UNTITLED SKETCH",
            style = MaterialTheme.typography.labelSmall,
            color = Paper.copy(alpha = if (name != null) 0.85f else 0.5f),
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.padding(top = 4.dp)
        )
        Text(
            text = "Created ${SketchStorage.createdLabel(note)}",
            style = MaterialTheme.typography.labelSmall,
            color = Paper.copy(alpha = 0.5f),
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
    }
}
