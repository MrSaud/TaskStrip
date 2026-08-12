package com.saud.taskstrip.media

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.text.StaticLayout
import android.text.TextPaint
import androidx.core.content.FileProvider
import com.saud.taskstrip.data.Priority
import com.saud.taskstrip.data.TaskEntity
import com.saud.taskstrip.ui.components.formatEtaFull
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

object ShareImageRenderer {

    private const val WIDTH = 1080
    private const val MARGIN = 56

    fun renderTaskCard(task: TaskEntity): Bitmap {
        val paper = Color.rgb(0xF4, 0xEF, 0xE1)
        val bay = Color.rgb(0x14, 0x17, 0x1C)
        val ink = Color.rgb(0x26, 0x22, 0x20)
        val priorityColor = task.priority.argb()

        val cardLeft = MARGIN
        val cardRight = WIDTH - MARGIN
        val tabWidth = 20
        val contentLeft = cardLeft + tabWidth + 40
        val contentRight = cardRight - 32
        val contentWidth = contentRight - contentLeft

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
        val dividerPaint = Paint().apply {
            color = Color.argb(38, Color.red(ink), Color.green(ink), Color.blue(ink))
            strokeWidth = 2f
        }

        // --- measure content height first ---
        var y = 64f
        y += 64f // title row
        y += 24f // divider gap
        y += 20f + 34f // tag/due row

        var notesLayout: StaticLayout? = null
        if (task.notes.isNotBlank()) {
            y += 24f
            notesLayout = StaticLayout.Builder
                .obtain(task.notes, 0, task.notes.length, notesPaint, contentWidth)
                .setLineSpacing(6f, 1f)
                .build()
            y += notesLayout.height
        }

        y += 40f // progress bar
        y += 56f // footer
        val cardBottom = y + 48f

        val height = cardBottom.toInt() + MARGIN
        val bitmap = Bitmap.createBitmap(WIDTH, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        canvas.drawColor(bay)

        val cardTop = 0f
        val cardRectF = RectF(cardLeft.toFloat(), cardTop, cardRight.toFloat(), cardBottom)
        val cardPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = paper }
        canvas.drawRoundRect(cardRectF, 16f, 16f, cardPaint)

        val tabPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = priorityColor }
        canvas.save()
        canvas.clipRect(cardLeft.toFloat(), cardTop, (cardLeft + tabWidth).toFloat(), cardBottom)
        canvas.drawRoundRect(cardRectF, 16f, 16f, tabPaint)
        canvas.restore()

        var cursorY = cardTop + 64f
        canvas.drawText(task.title.uppercase(), contentLeft.toFloat(), cursorY, titlePaint)
        val priorityText = task.priority.label
        val priorityTextWidth = priorityPaint.measureText(priorityText)
        canvas.drawText(priorityText, contentRight - priorityTextWidth, cursorY - 12f, priorityPaint)

        cursorY += 24f
        canvas.drawLine(contentLeft.toFloat(), cursorY, contentRight.toFloat(), cursorY, dividerPaint)
        cursorY += 20f + 34f

        var fieldX = contentLeft.toFloat()
        if (task.tags.isNotEmpty()) {
            val tagsText = task.tags.joinToString(", ") { it.uppercase() }
            canvas.drawText("TAGS", fieldX, cursorY - 34f, labelPaint)
            canvas.drawText(tagsText, fieldX, cursorY, valuePaint)
            fieldX += valuePaint.measureText(tagsText).coerceAtLeast(160f) + 48f
        }
        if (task.dueAt != null) {
            canvas.drawText("DUE", fieldX, cursorY - 34f, labelPaint)
            canvas.drawText(formatEtaFull(task.dueAt), fieldX, cursorY, valuePaint)
        }

        if (notesLayout != null) {
            cursorY += 24f
            canvas.save()
            canvas.translate(contentLeft.toFloat(), cursorY)
            notesLayout.draw(canvas)
            canvas.restore()
            cursorY += notesLayout.height
        }

        cursorY += 40f
        val trackPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.argb(26, Color.red(ink), Color.green(ink), Color.blue(ink))
        }
        val trackRect = RectF(contentLeft.toFloat(), cursorY - 8f, contentRight.toFloat(), cursorY)
        canvas.drawRoundRect(trackRect, 4f, 4f, trackPaint)
        val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = priorityColor }
        val fillWidth = contentWidth * (task.progress.coerceIn(0, 100) / 100f)
        canvas.drawRoundRect(
            RectF(contentLeft.toFloat(), cursorY - 8f, contentLeft + fillWidth, cursorY),
            4f,
            4f,
            fillPaint
        )
        canvas.drawText("${task.progress}% COMPLETE", contentLeft.toFloat(), cursorY + 40f, labelPaint)

        val filedDate = Instant.ofEpochMilli(task.createdAt).atZone(ZoneId.systemDefault())
            .format(DateTimeFormatter.ofPattern("dd MMM yyyy"))
        val footerText = "FILED $filedDate  ·  TASK STRIPS"
        canvas.drawText(footerText, contentLeft.toFloat(), cursorY + 96f, footerPaint)

        return bitmap
    }

    fun shareTask(context: Context, task: TaskEntity) {
        val bitmap = renderTaskCard(task)
        val dir = File(context.cacheDir, "shared").apply { mkdirs() }
        val file = File(dir, "strip_${task.id}_${System.currentTimeMillis()}.png")
        FileOutputStream(file).use { out -> bitmap.compress(Bitmap.CompressFormat.PNG, 100, out) }

        val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
        val shareIntent = Intent(Intent.ACTION_SEND).apply {
            type = "image/png"
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
