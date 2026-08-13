package com.saud.taskstrip.media

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.graphics.pdf.PdfDocument
import android.text.StaticLayout
import android.text.TextPaint
import androidx.core.content.FileProvider
import com.saud.taskstrip.data.Priority
import com.saud.taskstrip.data.TaskEntity
import com.saud.taskstrip.ui.components.formatEtaFull
import com.saud.taskstrip.ui.components.formatTimestampFull
import java.io.File
import java.io.FileOutputStream
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

private fun Priority.argb(): Int = when (this) {
    Priority.URGENT -> Color.rgb(0xC0, 0x39, 0x2B)
    Priority.HIGH -> Color.rgb(0xE0, 0x8E, 0x2D)
    Priority.NORMAL -> Color.rgb(0x3D, 0x7A, 0x5C)
    Priority.LOW -> Color.rgb(0x5B, 0x6B, 0x7A)
}

/**
 * Renders a task strip to a multi-page PDF and shares it. Unlike a single tall bitmap, this
 * paginates the content across A4 pages — the activity log flows entry-by-entry onto as many
 * pages as it needs, and text stays vector-crisp at any zoom or print size.
 *
 * Built on the framework's [PdfDocument], so it pulls in no extra dependencies.
 */
object SharePdfRenderer {

    // A4 portrait proportions at a 1080-unit width (1080 * 297/210 ≈ 1527).
    private const val PAGE_W = 1080
    private const val PAGE_H = 1527
    private const val MARGIN = 56
    private const val TAB_WIDTH = 20

    // A self-contained slice of the strip that knows its own height and how to paint itself at a
    // given vertical offset. The paginator packs these onto pages top-to-bottom.
    private class Block(val height: Float, val draw: (canvas: Canvas, top: Float) -> Unit)

    fun renderTaskPdf(task: TaskEntity): PdfDocument {
        val paper = Color.rgb(0xF4, 0xEF, 0xE1)
        val bay = Color.rgb(0x14, 0x17, 0x1C)
        val ink = Color.rgb(0x26, 0x22, 0x20)
        val priorityColor = task.priority.argb()

        val cardLeft = MARGIN.toFloat()
        val cardRight = (PAGE_W - MARGIN).toFloat()
        val cardTop = MARGIN.toFloat()
        val cardBottom = (PAGE_H - MARGIN).toFloat()

        val contentLeft = MARGIN + TAB_WIDTH + 40f
        val contentRight = (PAGE_W - MARGIN) - 32f
        val contentWidth = (contentRight - contentLeft).toInt()

        // Content is laid out between these two rails; blocks that don't fit roll to the next page.
        val contentTop = MARGIN + 64f
        val contentBottom = (PAGE_H - MARGIN) - 64f

        val titlePaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            color = ink
            textSize = 54f
            typeface = Typeface.create(Typeface.MONOSPACE, Typeface.BOLD)
        }
        val labelPaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.argb(140, Color.red(ink), Color.green(ink), Color.blue(ink))
            textSize = 26f
            typeface = Typeface.MONOSPACE
            letterSpacing = 0.08f
        }
        val valuePaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            color = ink
            textSize = 34f
            typeface = Typeface.create(Typeface.MONOSPACE, Typeface.BOLD)
        }
        val notesPaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.argb(190, Color.red(ink), Color.green(ink), Color.blue(ink))
            textSize = 32f
            typeface = Typeface.MONOSPACE
        }
        val priorityPaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            color = priorityColor
            textSize = 30f
            typeface = Typeface.create(Typeface.MONOSPACE, Typeface.BOLD)
        }
        val footerPaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.argb(255, 180, 180, 180)
            textSize = 24f
            typeface = Typeface.MONOSPACE
        }
        val pageNumPaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.argb(90, Color.red(ink), Color.green(ink), Color.blue(ink))
            textSize = 22f
            typeface = Typeface.MONOSPACE
            letterSpacing = 0.08f
        }
        val logTimePaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.argb(120, Color.red(ink), Color.green(ink), Color.blue(ink))
            textSize = 24f
            typeface = Typeface.MONOSPACE
            letterSpacing = 0.04f
        }
        val dividerPaint = Paint().apply {
            color = Color.argb(38, Color.red(ink), Color.green(ink), Color.blue(ink))
            strokeWidth = 2f
        }

        // --- Build the content as a linear stream of blocks ---
        val blocks = mutableListOf<Block>()

        // Title + priority + underline.
        blocks += Block(100f) { canvas, top ->
            canvas.drawText(task.title.uppercase(), contentLeft, top + 54f, titlePaint)
            val priorityText = task.priority.label
            val priorityTextWidth = priorityPaint.measureText(priorityText)
            canvas.drawText(priorityText, contentRight - priorityTextWidth, top + 42f, priorityPaint)
            canvas.drawLine(contentLeft, top + 80f, contentRight, top + 80f, dividerPaint)
        }

        // Tags / due.
        if (task.tags.isNotEmpty() || task.dueAt != null) {
            blocks += Block(76f) { canvas, top ->
                var fieldX = contentLeft
                if (task.tags.isNotEmpty()) {
                    val tagsText = task.tags.joinToString(", ") { it.uppercase() }
                    canvas.drawText("TAGS", fieldX, top + 22f, labelPaint)
                    canvas.drawText(tagsText, fieldX, top + 56f, valuePaint)
                    fieldX += valuePaint.measureText(tagsText).coerceAtLeast(160f) + 48f
                }
                if (task.dueAt != null) {
                    canvas.drawText("DUE", fieldX, top + 22f, labelPaint)
                    canvas.drawText(formatEtaFull(task.dueAt), fieldX, top + 56f, valuePaint)
                }
            }
        }

        // Notes.
        if (task.notes.isNotBlank()) {
            val notesLayout = StaticLayout.Builder
                .obtain(task.notes, 0, task.notes.length, notesPaint, contentWidth)
                .setLineSpacing(6f, 1f)
                .build()
            blocks += Block(notesLayout.height + 16f) { canvas, top ->
                canvas.save()
                canvas.translate(contentLeft, top + 12f)
                notesLayout.draw(canvas)
                canvas.restore()
            }
        }

        // Activity log — the part that actually grows without bound, so each entry is its own
        // block and the paginator spreads them across pages as needed. Newest first, matching the
        // edit screen.
        if (task.actionLog.isNotEmpty()) {
            blocks += Block(56f) { canvas, top ->
                canvas.drawLine(contentLeft, top + 16f, contentRight, top + 16f, dividerPaint)
                canvas.drawText("ACTIVITY LOG", contentLeft, top + 44f, labelPaint)
            }

            val sorted = task.actionLog.sortedByDescending { it.timestamp }
            sorted.forEachIndexed { index, entry ->
                val layout = StaticLayout.Builder
                    .obtain(entry.text, 0, entry.text.length, notesPaint, contentWidth)
                    .setLineSpacing(6f, 1f)
                    .build()
                val timeText = formatTimestampFull(entry.timestamp)
                val isLast = index == sorted.lastIndex
                val textH = layout.height.toFloat()
                val blockHeight = textH + 34f + if (isLast) 8f else 22f
                blocks += Block(blockHeight) { canvas, top ->
                    canvas.save()
                    canvas.translate(contentLeft, top)
                    layout.draw(canvas)
                    canvas.restore()
                    canvas.drawText(timeText, contentLeft, top + textH + 26f, logTimePaint)
                    if (!isLast) {
                        val dividerY = top + textH + 45f
                        canvas.drawLine(contentLeft, dividerY, contentRight, dividerY, dividerPaint)
                    }
                }
            }
        }

        // Progress bar + label.
        blocks += Block(64f) { canvas, top ->
            val barY = top + 8f
            val trackPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = Color.argb(26, Color.red(ink), Color.green(ink), Color.blue(ink))
            }
            canvas.drawRoundRect(RectF(contentLeft, barY - 8f, contentRight, barY), 4f, 4f, trackPaint)
            val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = priorityColor }
            val fillWidth = contentWidth * (task.progress.coerceIn(0, 100) / 100f)
            canvas.drawRoundRect(RectF(contentLeft, barY - 8f, contentLeft + fillWidth, barY), 4f, 4f, fillPaint)
            canvas.drawText("${task.progress}% COMPLETE", contentLeft, barY + 40f, labelPaint)
        }

        // Footer.
        val filedDate = Instant.ofEpochMilli(task.createdAt).atZone(ZoneId.systemDefault())
            .format(DateTimeFormatter.ofPattern("dd MMM yyyy"))
        blocks += Block(48f) { canvas, top ->
            canvas.drawText("FILED $filedDate  ·  TASK STRIPS", contentLeft, top + 24f, footerPaint)
        }

        // --- Paginate: pack blocks onto pages, breaking before any block that would overflow ---
        val pages = mutableListOf<MutableList<Pair<Block, Float>>>()
        var current = mutableListOf<Pair<Block, Float>>()
        var cursorY = contentTop
        for (block in blocks) {
            if (cursorY + block.height > contentBottom && cursorY > contentTop) {
                pages += current
                current = mutableListOf()
                cursorY = contentTop
            }
            current += block to cursorY
            cursorY += block.height
        }
        pages += current

        // --- Draw ---
        val document = PdfDocument()
        val totalPages = pages.size
        pages.forEachIndexed { index, pageBlocks ->
            val pageInfo = PdfDocument.PageInfo.Builder(PAGE_W, PAGE_H, index + 1).create()
            val page = document.startPage(pageInfo)
            val canvas = page.canvas

            // Card frame, repeated on every page so multi-page docs stay visually consistent.
            canvas.drawColor(bay)
            val cardRectF = RectF(cardLeft, cardTop, cardRight, cardBottom)
            canvas.drawRoundRect(cardRectF, 16f, 16f, Paint(Paint.ANTI_ALIAS_FLAG).apply { color = paper })
            canvas.save()
            canvas.clipRect(cardLeft, cardTop, cardLeft + TAB_WIDTH, cardBottom)
            canvas.drawRoundRect(cardRectF, 16f, 16f, Paint(Paint.ANTI_ALIAS_FLAG).apply { color = priorityColor })
            canvas.restore()

            if (totalPages > 1) {
                val pageLabel = "${index + 1} / $totalPages"
                val labelWidth = pageNumPaint.measureText(pageLabel)
                canvas.drawText(pageLabel, contentRight - labelWidth, cardBottom - 24f, pageNumPaint)
            }

            pageBlocks.forEach { (block, top) -> block.draw(canvas, top) }
            document.finishPage(page)
        }

        return document
    }

    fun shareTask(context: Context, task: TaskEntity) {
        val document = renderTaskPdf(task)
        val dir = File(context.cacheDir, "shared").apply { mkdirs() }
        val file = File(dir, "strip_${task.id}_${System.currentTimeMillis()}.pdf")
        FileOutputStream(file).use { out -> document.writeTo(out) }
        document.close()

        val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
        val shareIntent = Intent(Intent.ACTION_SEND).apply {
            type = "application/pdf"
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        val chooser = Intent.createChooser(shareIntent, "Share task")
        if (context !is Activity) {
            chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(chooser)
    }
}
