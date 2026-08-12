package com.saud.taskstrip.ui.components

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.widget.MediaController
import android.widget.Toast
import android.widget.VideoView
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectTransformGestures
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
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.Image
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AddAPhoto
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.PhotoCamera
import androidx.compose.material.icons.filled.PlayCircle
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material.icons.filled.UploadFile
import androidx.compose.material.icons.filled.Videocam
import androidx.compose.material.icons.filled.VideoLibrary
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.ui.text.style.TextOverflow
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import coil.compose.AsyncImage
import com.saud.taskstrip.media.AudioDuration
import com.saud.taskstrip.media.DocumentOpener
import com.saud.taskstrip.media.MediaStorage
import com.saud.taskstrip.media.VideoThumbnail
import com.saud.taskstrip.media.VoicePlayer
import com.saud.taskstrip.media.VoiceRecorder
import com.saud.taskstrip.ui.theme.AmberTab
import com.saud.taskstrip.ui.theme.InkColor
import com.saud.taskstrip.ui.theme.Paper
import com.saud.taskstrip.ui.theme.PriorityUrgent
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import java.io.File

private val DOCUMENT_MIME_TYPES = arrayOf(
    "application/pdf",
    "application/msword",
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    "text/csv",
    "application/vnd.ms-excel",
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
)

@Composable
fun AttachmentsSection(
    images: List<String>,
    onImagesChange: (List<String>) -> Unit,
    voiceNotes: List<String>,
    onVoiceNotesChange: (List<String>) -> Unit,
    documents: List<String>,
    onDocumentsChange: (List<String>) -> Unit,
    videos: List<String>,
    onVideosChange: (List<String>) -> Unit
) {
    val context = LocalContext.current
    var viewerIndex by remember { mutableStateOf<Int?>(null) }
    var videoViewerPath by remember { mutableStateOf<String?>(null) }
    // Saveable: the camera app backgrounds us during recording, which can get this process
    // killed — a plain `remember` here would silently lose the just-recorded video's path.
    var pendingVideoPath by rememberSaveable { mutableStateOf<String?>(null) }
    var pendingImagePath by rememberSaveable { mutableStateOf<String?>(null) }

    val photoPicker = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.PickMultipleVisualMedia()
    ) { uris: List<Uri> ->
        if (uris.isNotEmpty()) {
            val copied = uris.mapNotNull { MediaStorage.copyImageToLocal(context, it) }
            onImagesChange(images + copied)
        }
    }

    val photoCaptureLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.TakePicture()
    ) { success ->
        val path = pendingImagePath
        if (success && path != null) {
            onImagesChange(images + path)
        } else {
            path?.let { MediaStorage.deleteFile(it) }
        }
        pendingImagePath = null
    }

    Text("PHOTOS", style = MaterialTheme.typography.labelSmall, color = Paper.copy(alpha = 0.7f))
    Spacer(Modifier.height(6.dp))
    LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        items(images, key = { it }) { path ->
            val index = images.indexOf(path)
            Box(Modifier.size(72.dp)) {
                AsyncImage(
                    model = File(path),
                    contentDescription = "Photo ${index + 1}, tap to view",
                    contentScale = ContentScale.Crop,
                    modifier = Modifier
                        .size(72.dp)
                        .clip(RoundedCornerShape(4.dp))
                        .clickable { viewerIndex = index }
                )
                IconButton(
                    onClick = {
                        MediaStorage.deleteFile(path)
                        onImagesChange(images - path)
                    },
                    modifier = Modifier
                        .align(Alignment.TopEnd)
                        .size(22.dp)
                        .background(InkColor.copy(alpha = 0.7f), CircleShape)
                ) {
                    Icon(
                        Icons.Default.Close,
                        contentDescription = "Remove photo",
                        tint = Paper,
                        modifier = Modifier.size(14.dp)
                    )
                }
            }
        }
        item {
            Box(
                Modifier
                    .size(72.dp)
                    .clip(RoundedCornerShape(4.dp))
                    .background(Paper.copy(alpha = 0.08f))
                    .clickable {
                        val file = MediaStorage.newImageFile(context)
                        val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
                        pendingImagePath = file.absolutePath
                        try {
                            photoCaptureLauncher.launch(uri)
                        } catch (e: ActivityNotFoundException) {
                            Toast.makeText(context, "No camera app found on this device", Toast.LENGTH_SHORT).show()
                        }
                    },
                contentAlignment = Alignment.Center
            ) {
                Icon(Icons.Default.PhotoCamera, contentDescription = "Take photo", tint = Paper.copy(alpha = 0.6f))
            }
        }
        item {
            Box(
                Modifier
                    .size(72.dp)
                    .clip(RoundedCornerShape(4.dp))
                    .background(Paper.copy(alpha = 0.08f))
                    .clickable {
                        photoPicker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
                    },
                contentAlignment = Alignment.Center
            ) {
                Icon(Icons.Default.AddAPhoto, contentDescription = "Add photo from gallery", tint = Paper.copy(alpha = 0.6f))
            }
        }
    }

    Spacer(Modifier.height(18.dp))
    Text("VIDEOS", style = MaterialTheme.typography.labelSmall, color = Paper.copy(alpha = 0.7f))
    Spacer(Modifier.height(6.dp))

    val videoPicker = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.PickVisualMedia()
    ) { uri: Uri? ->
        if (uri != null) {
            MediaStorage.copyVideoToLocal(context, uri)?.let { onVideosChange(videos + it) }
        }
    }

    val videoCaptureLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.CaptureVideo()
    ) { success ->
        val path = pendingVideoPath
        if (success && path != null) {
            onVideosChange(videos + path)
        } else {
            path?.let { MediaStorage.deleteFile(it) }
        }
        pendingVideoPath = null
    }

    LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        items(videos, key = { it }) { path ->
            val thumb = remember(path) { VideoThumbnail.getFrame(path)?.asImageBitmap() }
            Box(Modifier.size(72.dp)) {
                Box(
                    Modifier
                        .size(72.dp)
                        .clip(RoundedCornerShape(4.dp))
                        .background(Paper.copy(alpha = 0.08f))
                        .clickable { videoViewerPath = path },
                    contentAlignment = Alignment.Center
                ) {
                    if (thumb != null) {
                        Image(
                            bitmap = thumb,
                            contentDescription = "Video, tap to play",
                            contentScale = ContentScale.Crop,
                            modifier = Modifier.size(72.dp)
                        )
                    }
                    Icon(Icons.Default.PlayCircle, contentDescription = null, tint = Paper)
                }
                IconButton(
                    onClick = {
                        MediaStorage.deleteFile(path)
                        onVideosChange(videos - path)
                    },
                    modifier = Modifier
                        .align(Alignment.TopEnd)
                        .size(22.dp)
                        .background(InkColor.copy(alpha = 0.7f), CircleShape)
                ) {
                    Icon(
                        Icons.Default.Close,
                        contentDescription = "Remove video",
                        tint = Paper,
                        modifier = Modifier.size(14.dp)
                    )
                }
            }
        }
        item {
            Box(
                Modifier
                    .size(72.dp)
                    .clip(RoundedCornerShape(4.dp))
                    .background(Paper.copy(alpha = 0.08f))
                    .clickable {
                        val file = MediaStorage.newVideoFile(context)
                        val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
                        pendingVideoPath = file.absolutePath
                        try {
                            videoCaptureLauncher.launch(uri)
                        } catch (e: ActivityNotFoundException) {
                            Toast.makeText(context, "No camera app found on this device", Toast.LENGTH_SHORT).show()
                        }
                    },
                contentAlignment = Alignment.Center
            ) {
                Icon(Icons.Default.Videocam, contentDescription = "Record video", tint = Paper.copy(alpha = 0.6f))
            }
        }
        item {
            Box(
                Modifier
                    .size(72.dp)
                    .clip(RoundedCornerShape(4.dp))
                    .background(Paper.copy(alpha = 0.08f))
                    .clickable {
                        videoPicker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.VideoOnly))
                    },
                contentAlignment = Alignment.Center
            ) {
                Icon(Icons.Default.VideoLibrary, contentDescription = "Add video from gallery", tint = Paper.copy(alpha = 0.6f))
            }
        }
    }

    Spacer(Modifier.height(18.dp))
    Text("DOCUMENTS", style = MaterialTheme.typography.labelSmall, color = Paper.copy(alpha = 0.7f))
    Spacer(Modifier.height(6.dp))

    val documentPicker = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.OpenMultipleDocuments()
    ) { uris: List<Uri> ->
        if (uris.isNotEmpty()) {
            val copied = uris.mapNotNull { MediaStorage.copyDocumentToLocal(context, it) }
            onDocumentsChange(documents + copied)
        }
    }

    Column {
        documents.forEach { path ->
            val file = remember(path) { File(path) }
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable {
                        try {
                            DocumentOpener.open(context, path)
                        } catch (e: ActivityNotFoundException) {
                            Toast.makeText(context, "No app on this device can open that file", Toast.LENGTH_SHORT).show()
                        }
                    }
            ) {
                Icon(Icons.Default.Description, contentDescription = null, tint = AmberTab)
                Spacer(Modifier.width(10.dp))
                Text(
                    text = file.name,
                    style = MaterialTheme.typography.bodyMedium,
                    color = Paper.copy(alpha = 0.8f),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f)
                )
                IconButton(onClick = {
                    MediaStorage.deleteDocument(path)
                    onDocumentsChange(documents - path)
                }) {
                    Icon(Icons.Default.Delete, contentDescription = "Remove ${file.name}", tint = Paper.copy(alpha = 0.6f))
                }
            }
        }
        OutlinedButton(
            onClick = { documentPicker.launch(DOCUMENT_MIME_TYPES) },
            modifier = Modifier.height(48.dp)
        ) {
            Icon(Icons.Default.UploadFile, contentDescription = null, tint = Paper.copy(alpha = 0.7f))
            Spacer(Modifier.width(8.dp))
            Text(
                text = if (documents.isEmpty()) "ADD DOCUMENT" else "ADD ANOTHER DOCUMENT",
                style = MaterialTheme.typography.bodyMedium
            )
        }
    }

    Spacer(Modifier.height(18.dp))
    Text("VOICE NOTES", style = MaterialTheme.typography.labelSmall, color = Paper.copy(alpha = 0.7f))
    Spacer(Modifier.height(6.dp))

    var hasAudioPermission by remember {
        mutableStateOf(
            ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) ==
                PackageManager.PERMISSION_GRANTED
        )
    }
    val recorder = remember { VoiceRecorder(context) }
    val player = remember { VoicePlayer() }
    var isRecording by remember { mutableStateOf(false) }
    var playingPath by remember { mutableStateOf<String?>(null) }

    val permissionLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestPermission()
    ) { granted ->
        hasAudioPermission = granted
        if (granted) {
            recorder.start()
            isRecording = true
        }
    }

    DisposableEffect(Unit) {
        onDispose {
            recorder.cancel()
            player.stop()
        }
    }

    Column {
        voiceNotes.forEachIndexed { index, path ->
            val totalMs = remember(path) { AudioDuration.getMillis(path) }
            var remainingMs by remember(path) { mutableLongStateOf(totalMs) }
            val isPlayingThis = playingPath == path

            LaunchedEffect(isPlayingThis) {
                if (isPlayingThis) {
                    while (isActive) {
                        val remaining = (totalMs - player.positionMillis()).coerceAtLeast(0)
                        remainingMs = remaining
                        delay(200)
                    }
                } else {
                    remainingMs = totalMs
                }
            }

            Row(verticalAlignment = Alignment.CenterVertically) {
                IconButton(onClick = {
                    if (isPlayingThis) {
                        player.stop()
                        playingPath = null
                    } else {
                        playingPath = path
                        player.play(path) { playingPath = null }
                    }
                }) {
                    Icon(
                        imageVector = if (isPlayingThis) Icons.Default.Pause else Icons.Default.PlayArrow,
                        contentDescription = "Play voice note ${index + 1}",
                        tint = AmberTab
                    )
                }
                AudioWaveform(playing = isPlayingThis, modifier = Modifier.padding(end = 10.dp))
                Text(
                    text = "VOICE NOTE ${index + 1}",
                    style = MaterialTheme.typography.bodyMedium,
                    color = Paper.copy(alpha = 0.8f),
                    modifier = Modifier.weight(1f)
                )
                Text(
                    text = formatDurationMinSec(remainingMs),
                    style = MaterialTheme.typography.labelSmall,
                    color = if (isPlayingThis) AmberTab else Paper.copy(alpha = 0.5f),
                    modifier = Modifier.padding(end = 4.dp)
                )
                IconButton(onClick = {
                    if (playingPath == path) {
                        player.stop()
                        playingPath = null
                    }
                    MediaStorage.deleteFile(path)
                    onVoiceNotesChange(voiceNotes - path)
                }) {
                    Icon(Icons.Default.Delete, contentDescription = "Remove voice note ${index + 1}", tint = Paper.copy(alpha = 0.6f))
                }
            }
        }

        if (isRecording) {
            OutlinedButton(
                onClick = {
                    val file = recorder.stop()
                    isRecording = false
                    if (file != null) {
                        onVoiceNotesChange(voiceNotes + file.absolutePath)
                    }
                },
                modifier = Modifier.height(48.dp)
            ) {
                Icon(Icons.Default.Stop, contentDescription = null, tint = PriorityUrgent)
                Spacer(Modifier.width(8.dp))
                Text("STOP RECORDING", style = MaterialTheme.typography.bodyMedium)
            }
        } else {
            OutlinedButton(
                onClick = {
                    if (hasAudioPermission) {
                        recorder.start()
                        isRecording = true
                    } else {
                        permissionLauncher.launch(Manifest.permission.RECORD_AUDIO)
                    }
                },
                modifier = Modifier.height(48.dp)
            ) {
                Icon(Icons.Default.Mic, contentDescription = null, tint = Paper.copy(alpha = 0.7f))
                Spacer(Modifier.width(8.dp))
                Text(
                    text = if (voiceNotes.isEmpty()) "RECORD VOICE NOTE" else "ADD ANOTHER VOICE NOTE",
                    style = MaterialTheme.typography.bodyMedium
                )
            }
        }
    }

    val openIndex = viewerIndex
    if (openIndex != null) {
        ImageViewerDialog(
            images = images,
            startIndex = openIndex,
            onDismiss = { viewerIndex = null },
            onDelete = { path ->
                MediaStorage.deleteFile(path)
                val updated = images - path
                onImagesChange(updated)
                if (updated.isEmpty()) viewerIndex = null
            }
        )
    }

    val openVideoPath = videoViewerPath
    if (openVideoPath != null) {
        VideoViewerDialog(
            path = openVideoPath,
            onDismiss = { videoViewerPath = null },
            onDelete = {
                MediaStorage.deleteFile(openVideoPath)
                onVideosChange(videos - openVideoPath)
                videoViewerPath = null
            }
        )
    }
}

@Composable
private fun VideoViewerDialog(path: String, onDismiss: () -> Unit, onDelete: () -> Unit) {
    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Box(
            Modifier
                .fillMaxSize()
                .background(InkColor.copy(alpha = 0.97f))
        ) {
            AndroidView(
                factory = { ctx ->
                    VideoView(ctx).apply {
                        setVideoPath(path)
                        val controller = MediaController(ctx)
                        controller.setAnchorView(this)
                        setMediaController(controller)
                        setOnPreparedListener { it.start() }
                    }
                },
                modifier = Modifier.fillMaxSize()
            )
            IconButton(
                onClick = onDismiss,
                modifier = Modifier.align(Alignment.TopStart).padding(12.dp)
            ) {
                Icon(Icons.Default.Close, contentDescription = "Close", tint = Paper)
            }
            IconButton(
                onClick = onDelete,
                modifier = Modifier.align(Alignment.BottomEnd).padding(20.dp)
            ) {
                Icon(Icons.Default.Delete, contentDescription = "Delete this video", tint = Paper)
            }
        }
    }
}

@OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class)
@Composable
private fun ImageViewerDialog(
    images: List<String>,
    startIndex: Int,
    onDismiss: () -> Unit,
    onDelete: (String) -> Unit
) {
    val context = LocalContext.current
    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        val pagerState = rememberPagerState(initialPage = startIndex) { images.size }
        // Disabled while the current page is zoomed in, so a pan-to-look-around drag doesn't
        // also flip to the next photo — swiping to change photos only works back at 1x.
        var currentPageZoomed by remember { mutableStateOf(false) }
        Box(
            Modifier
                .fillMaxSize()
                .background(InkColor.copy(alpha = 0.97f))
        ) {
            if (images.isNotEmpty()) {
                HorizontalPager(
                    state = pagerState,
                    modifier = Modifier.fillMaxSize(),
                    userScrollEnabled = !currentPageZoomed
                ) { page ->
                    ZoomableImage(
                        path = images[page],
                        contentDescription = "Photo ${page + 1} of ${images.size}",
                        onZoomedChange = { zoomed ->
                            if (page == pagerState.currentPage) currentPageZoomed = zoomed
                        }
                    )
                }
                Text(
                    text = "${pagerState.currentPage + 1} / ${images.size}",
                    style = MaterialTheme.typography.bodyMedium,
                    color = Paper,
                    modifier = Modifier
                        .align(Alignment.TopCenter)
                        .padding(top = 20.dp)
                )
                Row(
                    modifier = Modifier.align(Alignment.BottomEnd).padding(20.dp),
                    horizontalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    IconButton(onClick = {
                        val file = File(images[pagerState.currentPage])
                        val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
                        val shareIntent = Intent(Intent.ACTION_SEND).apply {
                            type = "image/*"
                            putExtra(Intent.EXTRA_STREAM, uri)
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        }
                        context.startActivity(Intent.createChooser(shareIntent, "Share photo"))
                    }) {
                        Icon(Icons.Default.Share, contentDescription = "Share this photo", tint = Paper)
                    }
                    IconButton(onClick = { onDelete(images[pagerState.currentPage]) }) {
                        Icon(Icons.Default.Delete, contentDescription = "Delete this photo", tint = Paper)
                    }
                }
            }
            IconButton(
                onClick = onDismiss,
                modifier = Modifier.align(Alignment.TopStart).padding(12.dp)
            ) {
                Icon(Icons.Default.Close, contentDescription = "Close", tint = Paper)
            }
        }
    }
}

// Pinch to zoom (1x-5x), drag to pan while zoomed, double-tap to toggle zoom. Pan is clamped so
// the image can't be dragged entirely off-screen, and everything resets when scale returns to 1x.
@Composable
private fun ZoomableImage(
    path: String,
    contentDescription: String,
    onZoomedChange: (Boolean) -> Unit
) {
    var scale by remember(path) { mutableFloatStateOf(1f) }
    var offset by remember(path) { mutableStateOf(Offset.Zero) }
    var containerSize by remember { mutableStateOf(IntSize.Zero) }

    fun clampOffset(rawOffset: Offset, currentScale: Float): Offset {
        val maxX = (containerSize.width * (currentScale - 1f) / 2f).coerceAtLeast(0f)
        val maxY = (containerSize.height * (currentScale - 1f) / 2f).coerceAtLeast(0f)
        return Offset(rawOffset.x.coerceIn(-maxX, maxX), rawOffset.y.coerceIn(-maxY, maxY))
    }

    AsyncImage(
        model = File(path),
        contentDescription = contentDescription,
        contentScale = ContentScale.Fit,
        modifier = Modifier
            .fillMaxSize()
            .onSizeChanged { containerSize = it }
            .graphicsLayer {
                scaleX = scale
                scaleY = scale
                translationX = offset.x
                translationY = offset.y
            }
            .pointerInput(path) {
                detectTransformGestures { _, pan, zoom, _ ->
                    val newScale = (scale * zoom).coerceIn(1f, 5f)
                    scale = newScale
                    offset = if (newScale <= 1f) Offset.Zero else clampOffset(offset + pan * newScale, newScale)
                    onZoomedChange(newScale > 1.01f)
                }
            }
            .pointerInput(path) {
                detectTapGestures(onDoubleTap = {
                    val zoomedIn = scale > 1f
                    scale = if (zoomedIn) 1f else 3f
                    offset = Offset.Zero
                    onZoomedChange(!zoomedIn)
                })
            }
    )
}

// Stylized playback indicator — not real amplitude data, just a set of bars that pulse at
// staggered rates while playing to read clearly as "audio is running" at a glance.
@Composable
private fun AudioWaveform(playing: Boolean, modifier: Modifier = Modifier) {
    Row(
        modifier = modifier.height(18.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(3.dp)
    ) {
        repeat(4) { index ->
            val heightFraction = if (playing) {
                val transition = rememberInfiniteTransition(label = "wave$index")
                val animated by transition.animateFloat(
                    initialValue = 0.25f,
                    targetValue = 1f,
                    animationSpec = infiniteRepeatable(
                        animation = tween(durationMillis = 320 + index * 90, easing = LinearEasing),
                        repeatMode = RepeatMode.Reverse
                    ),
                    label = "bar$index"
                )
                animated
            } else {
                0.25f
            }
            Box(
                Modifier
                    .width(3.dp)
                    .fillMaxHeight(heightFraction)
                    .background(AmberTab, RoundedCornerShape(1.dp))
            )
        }
    }
}
