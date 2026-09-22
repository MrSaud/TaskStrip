package com.saud.taskstrip.backup

import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

data class DriveBackupFile(val id: String, val name: String, val createdTime: String, val size: Long)

/** Thin wrapper over the Drive v3 REST API — no generated client library, matching the rest of
 * this app's habit of talking to REST APIs directly via HttpURLConnection. */
object DriveApi {
    private const val FOLDER_NAME = "TaskStripBackups"
    private const val FOLDER_MIME = "application/vnd.google-apps.folder"
    private const val BASE = "https://www.googleapis.com/drive/v3"
    private const val UPLOAD_BASE = "https://www.googleapis.com/upload/drive/v3"

    private fun connection(urlString: String, accessToken: String, method: String): HttpURLConnection {
        val connection = URL(urlString).openConnection() as HttpURLConnection
        connection.requestMethod = method
        connection.setRequestProperty("Authorization", "Bearer $accessToken")
        connection.connectTimeout = 15000
        connection.readTimeout = 20000
        return connection
    }

    suspend fun ensureBackupFolder(accessToken: String): String? = withContext(Dispatchers.IO) {
        val query = URLEncoder.encode(
            "mimeType='$FOLDER_MIME' and name='$FOLDER_NAME' and trashed=false", "UTF-8"
        )
        val listUrl = "$BASE/files?q=$query&spaces=drive&fields=files(id,name)"
        val existing = runCatching {
            val connection = connection(listUrl, accessToken, "GET")
            val body = connection.inputStream.bufferedReader().use { it.readText() }
            connection.disconnect()
            JSONObject(body).getJSONArray("files")
        }.getOrNull()

        if (existing != null && existing.length() > 0) {
            return@withContext existing.getJSONObject(0).getString("id")
        }

        return@withContext runCatching {
            val connection = connection("$BASE/files?fields=id", accessToken, "POST")
            connection.doOutput = true
            connection.setRequestProperty("Content-Type", "application/json; charset=UTF-8")
            val metadata = JSONObject().apply {
                put("name", FOLDER_NAME)
                put("mimeType", FOLDER_MIME)
            }
            connection.outputStream.use { it.write(metadata.toString().toByteArray()) }
            val body = connection.inputStream.bufferedReader().use { it.readText() }
            connection.disconnect()
            JSONObject(body).getString("id")
        }.getOrNull()
    }

    suspend fun uploadBackup(accessToken: String, folderId: String, file: File, fileName: String): Boolean =
        withContext(Dispatchers.IO) {
            runCatching {
                val boundary = "taskstrip-${UUID.randomUUID()}"
                val metadata = JSONObject().apply {
                    put("name", fileName)
                    put("parents", org.json.JSONArray().put(folderId))
                }
                val connection = connection("$UPLOAD_BASE/files?uploadType=multipart", accessToken, "POST")
                connection.doOutput = true
                connection.setRequestProperty("Content-Type", "multipart/related; boundary=$boundary")

                connection.outputStream.use { out ->
                    out.write("--$boundary\r\n".toByteArray())
                    out.write("Content-Type: application/json; charset=UTF-8\r\n\r\n".toByteArray())
                    out.write(metadata.toString().toByteArray())
                    out.write("\r\n--$boundary\r\n".toByteArray())
                    out.write("Content-Type: application/zip\r\n\r\n".toByteArray())
                    file.inputStream().use { it.copyTo(out) }
                    out.write("\r\n--$boundary--".toByteArray())
                }

                val code = connection.responseCode
                connection.disconnect()
                code in 200..299
            }.getOrDefault(false)
        }

    suspend fun listBackups(accessToken: String, folderId: String): List<DriveBackupFile> =
        withContext(Dispatchers.IO) {
            runCatching {
                val query = URLEncoder.encode("'$folderId' in parents and trashed=false", "UTF-8")
                val url = "$BASE/files?q=$query&spaces=drive&fields=files(id,name,createdTime,size)&orderBy=createdTime desc"
                val connection = connection(url, accessToken, "GET")
                val body = connection.inputStream.bufferedReader().use { it.readText() }
                connection.disconnect()
                val files = JSONObject(body).getJSONArray("files")
                (0 until files.length()).map { i ->
                    val obj = files.getJSONObject(i)
                    DriveBackupFile(
                        id = obj.getString("id"),
                        name = obj.getString("name"),
                        createdTime = obj.optString("createdTime"),
                        size = obj.optString("size", "0").toLongOrNull() ?: 0L
                    )
                }
            }.getOrDefault(emptyList())
        }

    suspend fun downloadBackup(accessToken: String, fileId: String, destination: File): Boolean =
        withContext(Dispatchers.IO) {
            runCatching {
                val connection = connection("$BASE/files/$fileId?alt=media", accessToken, "GET")
                connection.inputStream.use { input ->
                    destination.outputStream().use { output -> input.copyTo(output) }
                }
                connection.disconnect()
                true
            }.getOrDefault(false)
        }

    /** One named file inside the folder. The sync document is addressed by name because both apps
     * have to find the same file without either having been told its Drive id. */
    suspend fun findFile(accessToken: String, folderId: String, name: String): String? =
        withContext(Dispatchers.IO) {
            runCatching {
                val query = URLEncoder.encode(
                    "name='$name' and '$folderId' in parents and trashed=false", "UTF-8"
                )
                val url = "$BASE/files?q=$query&spaces=drive&fields=files(id,name)"
                val connection = connection(url, accessToken, "GET")
                val body = connection.inputStream.bufferedReader().use { it.readText() }
                connection.disconnect()
                val files = JSONObject(body).getJSONArray("files")
                if (files.length() == 0) null else files.getJSONObject(0).getString("id")
            }.getOrNull()
        }

    suspend fun downloadText(accessToken: String, fileId: String): String? =
        withContext(Dispatchers.IO) {
            runCatching {
                val connection = connection("$BASE/files/$fileId?alt=media", accessToken, "GET")
                val body = connection.inputStream.bufferedReader().use { it.readText() }
                connection.disconnect()
                body
            }.getOrNull()
        }

    /** Creates the file and returns its id. */
    suspend fun uploadText(
        accessToken: String,
        folderId: String,
        fileName: String,
        contents: String,
        mimeType: String
    ): String? = withContext(Dispatchers.IO) {
        runCatching {
            val boundary = "taskstrip-${UUID.randomUUID()}"
            val metadata = JSONObject().apply {
                put("name", fileName)
                put("parents", org.json.JSONArray().put(folderId))
            }
            val connection = connection("$UPLOAD_BASE/files?uploadType=multipart&fields=id", accessToken, "POST")
            connection.doOutput = true
            connection.setRequestProperty("Content-Type", "multipart/related; boundary=$boundary")
            connection.outputStream.use { out ->
                out.write("--$boundary\r\n".toByteArray())
                out.write("Content-Type: application/json; charset=UTF-8\r\n\r\n".toByteArray())
                out.write(metadata.toString().toByteArray())
                out.write("\r\n--$boundary\r\n".toByteArray())
                out.write("Content-Type: $mimeType; charset=UTF-8\r\n\r\n".toByteArray())
                out.write(contents.toByteArray(Charsets.UTF_8))
                out.write("\r\n--$boundary--".toByteArray())
            }
            val body = connection.inputStream.bufferedReader().use { it.readText() }
            connection.disconnect()
            JSONObject(body).getString("id")
        }.getOrNull()
    }

    /** Replaces a file's contents, keeping its id. A delete-and-recreate would do the same job
     * until two devices did it at once, and then there would be two sync documents and no way to
     * say which is the real one. */
    suspend fun replaceText(
        accessToken: String,
        fileId: String,
        contents: String,
        mimeType: String
    ): Boolean = withContext(Dispatchers.IO) {
        runCatching {
            // POST with an override header, not PATCH: HttpURLConnection rejects PATCH outright
            // with a ProtocolException, and runCatching would have turned that into a silent
            // "push failed" that looked exactly like a network problem. Google's APIs honour
            // X-HTTP-Method-Override for precisely this reason.
            val connection = connection("$UPLOAD_BASE/files/$fileId?uploadType=media", accessToken, "POST")
            connection.setRequestProperty("X-HTTP-Method-Override", "PATCH")
            connection.doOutput = true
            connection.setRequestProperty("Content-Type", "$mimeType; charset=UTF-8")
            connection.outputStream.use { it.write(contents.toByteArray(Charsets.UTF_8)) }
            val code = connection.responseCode
            connection.disconnect()
            code in 200..299
        }.getOrDefault(false)
    }

    suspend fun deleteBackup(accessToken: String, fileId: String): Boolean = withContext(Dispatchers.IO) {
        runCatching {
            val connection = connection("$BASE/files/$fileId", accessToken, "DELETE")
            val code = connection.responseCode
            connection.disconnect()
            code in 200..299
        }.getOrDefault(false)
    }
}
