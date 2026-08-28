package com.saud.taskstrip.network

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import com.saud.taskstrip.backup.BackupCrypto
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withTimeoutOrNull
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import kotlin.coroutines.resume

// Implements macos/PROTOCOL.md (v1) — see that file for the wire format this must match exactly.
private const val SERVICE_TYPE = "_taskstrip._tcp"
private const val DISCOVERY_TIMEOUT_MS = 4_000L
private const val CONNECT_TIMEOUT_MS = 3_000
private const val SOURCE = "taskstrip-android"

sealed class ClipboardSyncResult {
    data class Sent(val deviceName: String) : ClipboardSyncResult()
    object NotFound : ClipboardSyncResult()
    object NotConfigured : ClipboardSyncResult()
    data class Failed(val reason: String) : ClipboardSyncResult()
}

/** Pushes a clipboard snippet to whichever desktop is currently advertising `_taskstrip._tcp` on
 * this LAN — see macos/PROTOCOL.md. Discovery is done fresh per call (a few seconds) rather than
 * kept running in the background, since Android would kill a long-lived listener anyway without
 * a foreground service, and a clipboard push isn't latency-sensitive enough to need one. */
object ClipboardSyncSender {

    suspend fun send(context: Context, text: String, label: String): ClipboardSyncResult {
        val pairingCode = ClipboardSyncStore.getPairingCode(context)
        if (pairingCode.isNullOrBlank()) return ClipboardSyncResult.NotConfigured

        val service = discoverService(context) ?: return ClipboardSyncResult.NotFound
        val host = service.host?.hostAddress ?: return ClipboardSyncResult.NotFound

        return try {
            val plaintext = JSONObject().apply {
                put("text", text)
                put("label", label)
                put("sentAt", System.currentTimeMillis())
                put("source", SOURCE)
            }.toString()
            val encrypted = BackupCrypto.encrypt(plaintext, pairingCode)
            val envelope = JSONObject().apply {
                put("salt", encrypted.salt)
                put("iv", encrypted.iv)
                put("cipher", encrypted.cipher)
            }.toString().toByteArray(Charsets.UTF_8)

            val url = URL("http://$host:${service.port}/clip")
            val connection = (url.openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                doOutput = true
                connectTimeout = CONNECT_TIMEOUT_MS
                readTimeout = CONNECT_TIMEOUT_MS
                setRequestProperty("Content-Type", "application/json")
            }
            connection.outputStream.use { it.write(envelope) }
            val code = connection.responseCode
            connection.disconnect()
            if (code == HttpURLConnection.HTTP_OK) {
                ClipboardSyncResult.Sent(service.serviceName ?: "desktop")
            } else {
                ClipboardSyncResult.Failed(
                    when (code) {
                        401 -> "wrong pairing code"
                        408 -> "clocks are out of sync"
                        413 -> "snippet too large"
                        else -> "desktop rejected it (HTTP $code)"
                    }
                )
            }
        } catch (e: Exception) {
            ClipboardSyncResult.Failed(e.message ?: "network error")
        }
    }

    /** Resolves the first `_taskstrip._tcp` service seen within [DISCOVERY_TIMEOUT_MS], or null if
     * none answers in time — there's no persistent listener here, so "not found" just means no
     * desktop happened to be advertising during this one attempt. */
    private suspend fun discoverService(context: Context): NsdServiceInfo? {
        val nsdManager = context.applicationContext.getSystemService(Context.NSD_SERVICE) as? NsdManager
            ?: return null
        return withTimeoutOrNull(DISCOVERY_TIMEOUT_MS) {
            val found = discoverFirst(nsdManager) ?: return@withTimeoutOrNull null
            resolve(nsdManager, found)
        }
    }

    private suspend fun discoverFirst(nsdManager: NsdManager): NsdServiceInfo? =
        suspendCancellableCoroutine { continuation ->
            val listener = object : NsdManager.DiscoveryListener {
                private var resumed = false
                private fun finish(result: NsdServiceInfo?) {
                    if (resumed) return
                    resumed = true
                    runCatching { nsdManager.stopServiceDiscovery(this) }
                    continuation.resume(result)
                }
                override fun onDiscoveryStarted(serviceType: String) {}
                override fun onServiceFound(serviceInfo: NsdServiceInfo) {
                    if (serviceInfo.serviceType.contains("_taskstrip")) finish(serviceInfo)
                }
                override fun onServiceLost(serviceInfo: NsdServiceInfo) {}
                override fun onDiscoveryStopped(serviceType: String) {}
                override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) { finish(null) }
                override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) {}
            }
            continuation.invokeOnCancellation { runCatching { nsdManager.stopServiceDiscovery(listener) } }
            nsdManager.discoverServices(SERVICE_TYPE, NsdManager.PROTOCOL_DNS_SD, listener)
        }

    private suspend fun resolve(nsdManager: NsdManager, serviceInfo: NsdServiceInfo): NsdServiceInfo? =
        suspendCancellableCoroutine { continuation ->
            nsdManager.resolveService(serviceInfo, object : NsdManager.ResolveListener {
                override fun onResolveFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {
                    if (continuation.isActive) continuation.resume(null)
                }
                override fun onServiceResolved(serviceInfo: NsdServiceInfo) {
                    if (continuation.isActive) continuation.resume(serviceInfo)
                }
            })
        }
}
