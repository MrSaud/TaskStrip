package com.saud.taskstrip.data

import androidx.room.TypeConverter
import org.json.JSONArray
import org.json.JSONObject

// Unit separator control character: never appears in real file paths, safe to split on.
private const val LIST_DELIMITER = ""

class Converters {
    @TypeConverter
    fun fromPriority(priority: Priority): String = priority.name

    @TypeConverter
    fun toPriority(value: String): Priority = Priority.valueOf(value)

    @TypeConverter
    fun fromStringList(paths: List<String>): String = paths.joinToString(LIST_DELIMITER)

    @TypeConverter
    fun toStringList(value: String): List<String> =
        if (value.isEmpty()) emptyList() else value.split(LIST_DELIMITER)

    @TypeConverter
    fun fromContacts(contacts: List<TaskContact>): String {
        val arr = JSONArray()
        contacts.forEach { c ->
            arr.put(
                JSONObject().apply {
                    put("name", c.name)
                    put("email", c.email)
                    put("phone", c.phone)
                }
            )
        }
        return arr.toString()
    }

    @TypeConverter
    fun toContacts(value: String): List<TaskContact> {
        if (value.isBlank()) return emptyList()
        return try {
            val arr = JSONArray(value)
            (0 until arr.length()).map { i ->
                val obj = arr.getJSONObject(i)
                TaskContact(
                    name = obj.optString("name"),
                    email = obj.optString("email"),
                    phone = obj.optString("phone")
                )
            }
        } catch (e: Exception) {
            emptyList()
        }
    }

    @TypeConverter
    fun fromActionLog(entries: List<TaskActionLogEntry>): String {
        val arr = JSONArray()
        entries.forEach { e ->
            arr.put(
                JSONObject().apply {
                    put("text", e.text)
                    put("timestamp", e.timestamp)
                }
            )
        }
        return arr.toString()
    }

    @TypeConverter
    fun toActionLog(value: String): List<TaskActionLogEntry> {
        if (value.isBlank()) return emptyList()
        return try {
            val arr = JSONArray(value)
            (0 until arr.length()).map { i ->
                val obj = arr.getJSONObject(i)
                TaskActionLogEntry(
                    text = obj.optString("text"),
                    timestamp = obj.optLong("timestamp")
                )
            }
        } catch (e: Exception) {
            emptyList()
        }
    }
}
