package com.saud.taskstrip.ui.screens

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas as AndroidCanvas
import android.graphics.Color as AndroidColor
import android.graphics.Paint as AndroidPaint
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Undo
import androidx.compose.material.icons.filled.AddPhotoAlternate
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.DeleteSweep
import androidx.compose.material.icons.filled.Draw
import androidx.compose.material.icons.filled.NoteAdd
import androidx.compose.material.icons.filled.TouchApp
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.PointerType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import com.saud.taskstrip.media.SketchStorage
import com.saud.taskstrip.ui.theme.AmberTab
import com.saud.taskstrip.ui.theme.BayBackground
import com.saud.taskstrip.ui.theme.InkColor
import com.saud.taskstrip.ui.theme.Paper
import com.saud.taskstrip.ui.theme.PriorityNormal
import com.saud.taskstrip.ui.theme.PriorityUrgent
import java.io.File
import java.io.FileOutputStream

private data class SketchStroke(val points: List<Offset>, val color: Color, val widthPx: Float)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SketchCanvasScreen(fileName: String?, onDone: () -> Unit) {
    val context = LocalContext.current
    val noteDir = remember(fileName) {
        fileName?.let { SketchStorage.noteRef(context, it) } ?: SketchStorage.newNoteRef(context)
    }
    var pages by remember(noteDir) { mutableStateOf(SketchStorage.listPages(noteDir)) }
    // An index of pages.size (one past the last real page) means "a blank page not yet written
    // to disk" — true for a brand new note's first page, and again right after ADD PAGE until the
    // user draws something and it gets saved.
    var pageIndex by rememberSaveable(noteDir) { mutableStateOf((pages.size - 1).coerceAtLeast(0)) }

    val currentPageFile: File? = pages.getOrNull(pageIndex)
    // File equality is path-based, so overwriting a page's PNG in place (as image placement does)
    // doesn't change `currentPageFile` identity — bump this to force a reload from disk anyway.
    var backgroundReloadTick by remember { mutableIntStateOf(0) }
    val backgroundBitmap = remember(currentPageFile, backgroundReloadTick) {
        currentPageFile?.let { BitmapFactory.decodeFile(it.absolutePath)?.asImageBitmap() }
    }

    // Non-null while the user is positioning/resizing a just-picked image before it's baked into
    // the page background — drawing is suspended during this preview.
    var pendingImage by remember { mutableStateOf<ImageBitmap?>(null) }
    var pendingImageOffset by remember { mutableStateOf(Offset.Zero) }
    var pendingImageScale by remember { mutableFloatStateOf(1f) }

    // Keyed on the page's file identity (not just the index) so strokes correctly reset even when
    // the file at a given index changes without the index itself changing — e.g. deleting the
    // currently-viewed page shifts a different, later page into this same slot.
    val strokes = remember(pageIndex, currentPageFile, noteDir) { mutableStateListOf<SketchStroke>() }
    var currentStroke by remember { mutableStateOf<SketchStroke?>(null) }
    var penColor by remember { mutableStateOf(Color(0xFF262220)) }
    var penWidth by remember { mutableFloatStateOf(6f) }
    var canvasSize by remember { mutableStateOf(IntSize.Zero) }
    // Palm rejection: when on, only a stylus (S Pen etc.) draws — finger/palm touches are ignored.
    var stylusOnly by remember { mutableStateOf(true) }
    var showDeletePageConfirm by rememberSaveable { mutableStateOf(false) }

    // Saves the current page's strokes (if any changed) and refreshes `pages` — callers always
    // set `pageIndex` themselves right after, so this doesn't need to touch it.
    fun persistCurrentPage() {
        if (canvasSize.width <= 0 || canvasSize.height <= 0) return
        if (strokes.isEmpty()) return
        noteDir.mkdirs()
        SketchStorage.stampCreatedIfMissing(noteDir)
        val target = currentPageFile ?: SketchStorage.newPageFile(noteDir)
        saveSketch(target, canvasSize, currentPageFile, strokes)
        pages = SketchStorage.listPages(noteDir)
    }

    val imagePicker = rememberLauncherForActivityResult(
        ActivityResultContracts.PickVisualMedia()
    ) { uri: Uri? ->
        if (uri == null) return@rememberLauncherForActivityResult
        val bitmap = runCatching {
            context.contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it) }
        }.getOrNull()
        if (bitmap != null && canvasSize.width > 0 && canvasSize.height > 0) {
            // Start the picked image scaled to fit comfortably inside the page, centered, so the
            // user immediately sees the whole thing and just has to pinch/drag it into place.
            val fitScale = minOf(
                canvasSize.width * 0.7f / bitmap.width,
                canvasSize.height * 0.7f / bitmap.height,
                1f
            ).let { if (it.isNaN() || it <= 0f) 1f else it }
            pendingImageScale = fitScale
            pendingImageOffset = Offset(
                (canvasSize.width - bitmap.width * fitScale) / 2f,
                (canvasSize.height - bitmap.height * fitScale) / 2f
            )
            pendingImage = bitmap.asImageBitmap()
        }
    }

    // Bakes the in-progress placement into the page's PNG on top of anything already drawn, then
    // clears the in-memory strokes (now redundant with the freshly saved raster) so the user can
    // draw over the image immediately without navigating away and back.
    fun confirmImagePlacement() {
        val image = pendingImage ?: return
        if (canvasSize.width <= 0 || canvasSize.height <= 0) {
            pendingImage = null
            return
        }
        noteDir.mkdirs()
        SketchStorage.stampCreatedIfMissing(noteDir)
        val target = currentPageFile ?: SketchStorage.newPageFile(noteDir)
        saveSketch(target, canvasSize, currentPageFile, strokes)
        compositeImageOntoPage(target, canvasSize, image, pendingImageOffset, pendingImageScale)
        strokes.clear()
        pages = SketchStorage.listPages(noteDir)
        backgroundReloadTick++
        pendingImage = null
    }

    fun goToPage(index: Int) {
        persistCurrentPage()
        pageIndex = index.coerceIn(0, (pages.size - 1).coerceAtLeast(0))
    }

    Scaffold(
        containerColor = BayBackground,
        topBar = {
            // Wraps the whole bar (not just the title text) so the swipe target is the full
            // screen width — the title slot alone is squeezed to a narrow sliver between the
            // back arrow and up to 7 action icons, too small to reliably swipe on. A quick tap
            // still reaches the icons underneath since a drag detector only consumes once the
            // gesture clears touch-slop, so short taps pass through untouched.
            Box(
                Modifier.pointerInput(pageIndex, pages.size, pendingImage) {
                    if (pendingImage != null) return@pointerInput
                    val threshold = 56.dp.toPx()
                    var dragAccumPx = 0f
                    detectHorizontalDragGestures(
                        onDragStart = { dragAccumPx = 0f },
                        onDragCancel = { dragAccumPx = 0f },
                        onDragEnd = {
                            when {
                                dragAccumPx <= -threshold -> goToPage(pageIndex + 1)
                                dragAccumPx >= threshold -> goToPage(pageIndex - 1)
                            }
                        }
                    ) { change, dragAmount ->
                        change.consume()
                        dragAccumPx += dragAmount
                    }
                }
            ) {
                TopAppBar(
                    title = {
                        if (pendingImage != null) {
                            Text(
                                text = "PINCH TO RESIZE · DRAG TO MOVE",
                                style = MaterialTheme.typography.titleSmall,
                                color = Paper
                            )
                        } else {
                            // pageIndex can be pages.size (one past the last saved page) while a
                            // new, not-yet-saved blank page is being shown — count it too, or the
                            // header wrongly shows e.g. "1/1" while looking at the 2nd page.
                            val pageCount = maxOf(pages.size, pageIndex + 1)
                            val displayIndex = pageIndex + 1
                            Text(
                                text = "PAGE $displayIndex/$pageCount",
                                style = MaterialTheme.typography.titleMedium,
                                color = Paper
                            )
                        }
                    },
                    navigationIcon = {
                        IconButton(onClick = { if (pendingImage != null) pendingImage = null else onDone() }) {
                            Icon(
                                imageVector = if (pendingImage != null) Icons.Default.Close else Icons.AutoMirrored.Filled.ArrowBack,
                                contentDescription = if (pendingImage != null) "Cancel image placement" else "Back",
                                tint = Paper
                            )
                        }
                    },
                    actions = {
                        if (pendingImage != null) {
                            IconButton(onClick = { confirmImagePlacement() }) {
                                Icon(Icons.Default.Check, contentDescription = "Place image", tint = AmberTab)
                            }
                        } else {
                            IconButton(onClick = {
                                imagePicker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
                            }) {
                                Icon(Icons.Default.AddPhotoAlternate, contentDescription = "Insert image", tint = Paper)
                            }
                            IconButton(onClick = { stylusOnly = !stylusOnly }) {
                                Icon(
                                    imageVector = if (stylusOnly) Icons.Default.Draw else Icons.Default.TouchApp,
                                    contentDescription = if (stylusOnly) {
                                        "Pen only — tap to also allow finger touch"
                                    } else {
                                        "Finger and pen both draw — tap for pen only"
                                    },
                                    tint = if (stylusOnly) AmberTab else Paper
                                )
                            }
                            IconButton(
                                onClick = { if (strokes.isNotEmpty()) strokes.removeAt(strokes.lastIndex) }
                            ) {
                                Icon(Icons.AutoMirrored.Filled.Undo, contentDescription = "Undo", tint = Paper)
                            }
                            IconButton(onClick = { strokes.clear() }) {
                                Icon(Icons.Default.DeleteSweep, contentDescription = "Clear this page", tint = Paper)
                            }
                            if (pages.size > 1) {
                                IconButton(onClick = { showDeletePageConfirm = true }) {
                                    Icon(Icons.Default.Delete, contentDescription = "Delete this page", tint = Paper)
                                }
                            }
                            IconButton(onClick = {
                                persistCurrentPage()
                                pageIndex = pages.size
                            }) {
                                Icon(Icons.Default.NoteAdd, contentDescription = "Add page", tint = Paper)
                            }
                            IconButton(onClick = {
                                persistCurrentPage()
                                onDone()
                            }) {
                                Icon(Icons.Default.Check, contentDescription = "Save", tint = AmberTab)
                            }
                        }
                    },
                    colors = TopAppBarDefaults.topAppBarColors(containerColor = BayBackground)
                )
            }
        }
    ) { padding ->
        Box(Modifier.padding(padding).fillMaxSize()) {
            Box(
                Modifier
                    .fillMaxSize()
                    .padding(12.dp)
                    .background(Paper)
                    .onSizeChanged { canvasSize = it }
                    .pointerInput(stylusOnly, pageIndex, currentPageFile, pendingImage) {
                        if (pendingImage != null) return@pointerInput
                        awaitEachGesture {
                            val down = awaitFirstDown(requireUnconsumed = false)
                            if (stylusOnly && down.type != PointerType.Stylus && down.type != PointerType.Eraser) {
                                // Finger or palm while pen-only mode is on: ignore this touch
                                // entirely, don't start a stroke.
                                return@awaitEachGesture
                            }
                            down.consume()
                            currentStroke = SketchStroke(listOf(down.position), penColor, penWidth)
                            val pointerId = down.id
                            while (true) {
                                val event = awaitPointerEvent()
                                val change = event.changes.firstOrNull { it.id == pointerId } ?: break
                                change.consume()
                                val stroke = currentStroke
                                if (stroke != null) {
                                    currentStroke = stroke.copy(points = stroke.points + change.position)
                                }
                                if (!change.pressed) break
                            }
                            currentStroke?.let { strokes.add(it) }
                            currentStroke = null
                        }
                    }
            ) {
                if (backgroundBitmap != null) {
                    Canvas(Modifier.fillMaxSize()) {
                        drawImage(backgroundBitmap, dstSize = IntSize(size.width.toInt(), size.height.toInt()))
                    }
                }
                Canvas(Modifier.fillMaxSize()) {
                    (strokes + listOfNotNull(currentStroke)).forEach { stroke ->
                        if (stroke.points.size == 1) {
                            drawCircle(stroke.color, radius = stroke.widthPx / 2, center = stroke.points[0])
                        } else {
                            val path = Path().apply {
                                moveTo(stroke.points.first().x, stroke.points.first().y)
                                stroke.points.drop(1).forEach { lineTo(it.x, it.y) }
                            }
                            drawPath(
                                path,
                                color = stroke.color,
                                style = Stroke(width = stroke.widthPx, cap = androidx.compose.ui.graphics.StrokeCap.Round, join = androidx.compose.ui.graphics.StrokeJoin.Round)
                            )
                        }
                    }
                }
                pendingImage?.let { image ->
                    Canvas(
                        Modifier
                            .fillMaxSize()
                            .pointerInput(image) {
                                detectTransformGestures { _, pan, zoom, _ ->
                                    pendingImageScale = (pendingImageScale * zoom).coerceIn(0.1f, 10f)
                                    pendingImageOffset += pan
                                }
                            }
                    ) {
                        val dstW = (image.width * pendingImageScale).coerceAtLeast(1f)
                        val dstH = (image.height * pendingImageScale).coerceAtLeast(1f)
                        drawImage(
                            image = image,
                            dstOffset = IntOffset(pendingImageOffset.x.toInt(), pendingImageOffset.y.toInt()),
                            dstSize = IntSize(dstW.toInt(), dstH.toInt())
                        )
                        drawRect(
                            color = AmberTab,
                            topLeft = pendingImageOffset,
                            size = Size(dstW, dstH),
                            style = Stroke(width = 3f)
                        )
                    }
                }
            }
            if (pendingImage == null) {
                Row(
                    Modifier
                        .align(Alignment.BottomCenter)
                        .padding(bottom = 20.dp)
                        .clip(androidx.compose.foundation.shape.RoundedCornerShape(24.dp))
                        .background(BayBackground.copy(alpha = 0.9f))
                        .padding(horizontal = 16.dp, vertical = 10.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    listOf(InkColor, PriorityUrgent, PriorityNormal, AmberTab, Color(0xFF3E5C8A)).forEach { swatch ->
                        ColorSwatch(swatch, selected = penColor == swatch) { penColor = swatch }
                        Spacer(Modifier.width(10.dp))
                    }
                    Spacer(Modifier.width(8.dp))
                    WidthDot(6f, penWidth == 6f) { penWidth = 6f }
                    Spacer(Modifier.width(8.dp))
                    WidthDot(14f, penWidth == 14f) { penWidth = 14f }
                }
            }
        }
    }

    if (showDeletePageConfirm) {
        AlertDialog(
            onDismissRequest = { showDeletePageConfirm = false },
            title = { Text("DELETE THIS PAGE?", style = MaterialTheme.typography.titleMedium) },
            text = { Text("This page will be permanently deleted. This can't be undone.") },
            confirmButton = {
                TextButton(onClick = {
                    showDeletePageConfirm = false
                    currentPageFile?.let { SketchStorage.deletePage(it) }
                    pages = SketchStorage.listPages(noteDir)
                    pageIndex = pageIndex.coerceIn(0, (pages.size - 1).coerceAtLeast(0))
                }) { Text("DELETE", color = PriorityUrgent) }
            },
            dismissButton = {
                TextButton(onClick = { showDeletePageConfirm = false }) { Text("CANCEL") }
            }
        )
    }
}

@Composable
private fun ColorSwatch(color: Color, selected: Boolean, onClick: () -> Unit) {
    Box(
        Modifier
            .size(if (selected) 30.dp else 24.dp)
            .clip(CircleShape)
            .background(color)
            .clickable(onClick = onClick)
    )
}

@Composable
private fun WidthDot(widthPx: Float, selected: Boolean, onClick: () -> Unit) {
    Box(
        Modifier
            .size(30.dp)
            .clip(CircleShape)
            .background(if (selected) Paper.copy(alpha = 0.2f) else Color.Transparent)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center
    ) {
        Box(
            Modifier
                .size((widthPx / 2).dp)
                .clip(CircleShape)
                .background(Paper)
        )
    }
}

private fun saveSketch(
    target: File,
    canvasSize: IntSize,
    existingSourceForBackground: File?,
    strokes: List<SketchStroke>
) {
    if (canvasSize.width <= 0 || canvasSize.height <= 0) return
    val bitmap = Bitmap.createBitmap(canvasSize.width, canvasSize.height, Bitmap.Config.ARGB_8888)
    val canvas = AndroidCanvas(bitmap)
    canvas.drawColor(AndroidColor.rgb(0xF4, 0xEF, 0xE1))

    existingSourceForBackground?.let { file ->
        BitmapFactory.decodeFile(file.absolutePath)?.let { bg ->
            val scaled = Bitmap.createScaledBitmap(bg, canvasSize.width, canvasSize.height, true)
            canvas.drawBitmap(scaled, 0f, 0f, null)
        }
    }

    val paint = AndroidPaint(AndroidPaint.ANTI_ALIAS_FLAG).apply {
        style = AndroidPaint.Style.STROKE
        strokeCap = AndroidPaint.Cap.ROUND
        strokeJoin = AndroidPaint.Join.ROUND
    }
    strokes.forEach { stroke ->
        paint.color = AndroidColor.argb(
            (stroke.color.alpha * 255).toInt(),
            (stroke.color.red * 255).toInt(),
            (stroke.color.green * 255).toInt(),
            (stroke.color.blue * 255).toInt()
        )
        paint.strokeWidth = stroke.widthPx
        if (stroke.points.size == 1) {
            paint.style = AndroidPaint.Style.FILL
            canvas.drawCircle(stroke.points[0].x, stroke.points[0].y, stroke.widthPx / 2, paint)
            paint.style = AndroidPaint.Style.STROKE
        } else {
            val path = android.graphics.Path()
            path.moveTo(stroke.points.first().x, stroke.points.first().y)
            stroke.points.drop(1).forEach { path.lineTo(it.x, it.y) }
            canvas.drawPath(path, paint)
        }
    }

    FileOutputStream(target).use { out -> bitmap.compress(Bitmap.CompressFormat.PNG, 100, out) }
}

// Draws `image` at `offset`/`scale` on top of whatever `target` already contains (if anything)
// and rewrites `target` in place — used to bake a user-placed image into the page background.
private fun compositeImageOntoPage(
    target: File,
    canvasSize: IntSize,
    image: ImageBitmap,
    offset: Offset,
    scale: Float
) {
    if (canvasSize.width <= 0 || canvasSize.height <= 0) return
    val bitmap = Bitmap.createBitmap(canvasSize.width, canvasSize.height, Bitmap.Config.ARGB_8888)
    val canvas = AndroidCanvas(bitmap)
    canvas.drawColor(AndroidColor.rgb(0xF4, 0xEF, 0xE1))

    if (target.exists()) {
        BitmapFactory.decodeFile(target.absolutePath)?.let { base ->
            val scaledBase = Bitmap.createScaledBitmap(base, canvasSize.width, canvasSize.height, true)
            canvas.drawBitmap(scaledBase, 0f, 0f, null)
        }
    }

    val source = image.asAndroidBitmap()
    val dstW = (source.width * scale).toInt().coerceAtLeast(1)
    val dstH = (source.height * scale).toInt().coerceAtLeast(1)
    val scaledImage = Bitmap.createScaledBitmap(source, dstW, dstH, true)
    canvas.drawBitmap(scaledImage, offset.x, offset.y, null)

    FileOutputStream(target).use { out -> bitmap.compress(Bitmap.CompressFormat.PNG, 100, out) }
}
