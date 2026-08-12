package com.saud.taskstrip.quotes

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import java.net.HttpURLConnection
import java.net.URL

/** The only network call in this app — everything else stays fully on-device. */
object QuoteOfTheDayApi {

    suspend fun fetch(): Quote? = withContext(Dispatchers.IO) {
        var connection: HttpURLConnection? = null
        try {
            val url = URL("https://zenquotes.io/api/today")
            connection = (url.openConnection() as HttpURLConnection).apply {
                connectTimeout = 8000
                readTimeout = 8000
                requestMethod = "GET"
            }
            if (connection.responseCode != HttpURLConnection.HTTP_OK) return@withContext null
            val body = connection.inputStream.bufferedReader().use { it.readText() }
            val arr = JSONArray(body)
            if (arr.length() == 0) return@withContext null
            val obj = arr.getJSONObject(0)
            val text = obj.optString("q").trim()
            val author = obj.optString("a").trim()
            if (text.isBlank()) null else Quote(text, author.ifBlank { "Unknown" })
        } catch (e: Exception) {
            null
        } finally {
            connection?.disconnect()
        }
    }
}
