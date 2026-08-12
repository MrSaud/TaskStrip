package com.saud.taskstrip.quotes

import android.content.Context
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/** Caches one quote per calendar day so the board only hits the network once daily. */
object QuoteCache {
    private const val PREFS = "quote_of_day"
    private const val KEY_DATE = "date"
    private const val KEY_TEXT = "text"
    private const val KEY_AUTHOR = "author"

    private fun todayKey(): String = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())

    fun get(context: Context): Quote? {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (prefs.getString(KEY_DATE, null) != todayKey()) return null
        val text = prefs.getString(KEY_TEXT, null) ?: return null
        val author = prefs.getString(KEY_AUTHOR, null) ?: return null
        return Quote(text, author)
    }

    fun save(context: Context, quote: Quote) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString(KEY_DATE, todayKey())
            .putString(KEY_TEXT, quote.text)
            .putString(KEY_AUTHOR, quote.author)
            .apply()
    }
}
