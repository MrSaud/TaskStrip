package com.saud.taskstrip.quotes

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
import android.text.StaticLayout
import android.text.TextPaint
import android.text.Layout
import androidx.core.content.FileProvider
import java.io.File
import java.io.FileOutputStream

/** Renders the daily quote as a portrait card sized for a WhatsApp/Instagram status. */
object QuoteShareRenderer {

    private const val WIDTH = 1080
    private const val HEIGHT = 1920

    fun renderQuoteCard(quote: Quote): Bitmap {
        val bay = Color.rgb(0x14, 0x17, 0x1C)
        val paper = Color.rgb(0xF4, 0xEF, 0xE1)
        val ink = Color.rgb(0x26, 0x22, 0x20)
        val amber = Color.rgb(0xE0, 0x8E, 0x2D)

        val margin = 72
        val cardLeft = margin
        val cardRight = WIDTH - margin
        val contentWidth = cardRight - cardLeft - 96

        val labelPaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            color = amber
            textSize = 34f
            typeface = Typeface.create(Typeface.MONOSPACE, Typeface.BOLD)
            letterSpacing = 0.12f
        }
        val quotePaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            color = ink
            textSize = 56f
            typeface = Typeface.create(Typeface.MONOSPACE, Typeface.BOLD)
        }
        val authorPaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.argb(160, Color.red(ink), Color.green(ink), Color.blue(ink))
            textSize = 36f
            typeface = Typeface.MONOSPACE
        }
        val footerPaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.argb(255, 150, 150, 150)
            textSize = 26f
            typeface = Typeface.MONOSPACE
            letterSpacing = 0.1f
        }

        val quoteText = "“${quote.text}”"
        val quoteLayout = StaticLayout.Builder
            .obtain(quoteText, 0, quoteText.length, quotePaint, contentWidth)
            .setLineSpacing(12f, 1f)
            .setAlignment(Layout.Alignment.ALIGN_NORMAL)
            .build()
        val authorText = "— ${quote.author}"

        val bitmap = Bitmap.createBitmap(WIDTH, HEIGHT, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        canvas.drawColor(bay)

        val cardTop = (HEIGHT - quoteLayout.height) / 2f - 140f
        val cardBottom = cardTop + quoteLayout.height + 320f
        val cardPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = paper }
        canvas.drawRoundRect(
            cardLeft.toFloat(), cardTop, cardRight.toFloat(), cardBottom, 20f, 20f, cardPaint
        )

        var cursorY = cardTop + 96f
        canvas.drawText("QUOTE OF THE DAY", cardLeft + 48f, cursorY, labelPaint)

        cursorY += 72f
        canvas.save()
        canvas.translate(cardLeft + 48f, cursorY)
        quoteLayout.draw(canvas)
        canvas.restore()
        cursorY += quoteLayout.height + 56f

        canvas.drawText(authorText, cardLeft + 48f, cursorY, authorPaint)

        val footerText = "TASK STRIPS"
        val footerWidth = footerPaint.measureText(footerText)
        canvas.drawText(footerText, WIDTH - margin - footerWidth, HEIGHT - 80f, footerPaint)

        return bitmap
    }

    /** Tries WhatsApp's documented status-share intent first, falling back to the generic share sheet. */
    fun shareToWhatsAppStatus(context: Context, quote: Quote) {
        val bitmap = renderQuoteCard(quote)
        val dir = File(context.cacheDir, "shared").apply { mkdirs() }
        val file = File(dir, "quote_${System.currentTimeMillis()}.png")
        FileOutputStream(file).use { out -> bitmap.compress(Bitmap.CompressFormat.PNG, 100, out) }
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)

        val statusIntent = Intent().apply {
            action = "com.whatsapp.intent.action.SHARE_TO_STATUS"
            type = "image/png"
            putExtra(Intent.EXTRA_STREAM, uri)
            setPackage("com.whatsapp")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        try {
            context.startActivity(statusIntent)
        } catch (e: ActivityNotFoundException) {
            val shareIntent = Intent(Intent.ACTION_SEND).apply {
                type = "image/png"
                putExtra(Intent.EXTRA_STREAM, uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            val chooser = Intent.createChooser(shareIntent, "Share quote")
            if (context !is Activity) {
                chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(chooser)
        }
    }
}
