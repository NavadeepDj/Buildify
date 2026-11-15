package com.example.buildify_flutter

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import androidx.core.app.NotificationCompat

/** A quick tunnel dedicated to the authenticated Flutter voice bridge.
 * Never shares credentials, process state, or lifecycle with model hosting.
 */
class VoiceTunnelService : Service() {
    private val processLock = Any()
    private var process: Process? = null
    @Volatile private var generation = 0
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action != ACTION_START) {
            stopSelf()
            return START_NOT_STICKY
        }
        if (currentStatus == "running" || currentStatus == "starting") {
            return START_NOT_STICKY
        }
        try {
            startForeground(NOTIFICATION_ID, notification("Connecting voice tools"))
        } catch (_: Exception) {
            currentStatus = "failed"
            lastError = "Android could not keep the voice connection active. Open Buildify and retry."
            publicUrl = null
            stopSelf()
            return START_NOT_STICKY
        }
        currentStatus = "starting"
        lastError = null
        publicUrl = null
        val install = try { CloudflaredBinary.prepare(this) } catch (_: Exception) { null }
        if (install == null) {
            currentStatus = "failed"
            lastError = "Voice tunnel is unavailable for this device architecture."
            stopSelf()
            return START_NOT_STICKY
        }
        val activeGeneration = synchronized(processLock) { ++generation }
        mainHandler.postDelayed({
            if (activeGeneration == generation && currentStatus == "starting") {
                fail(activeGeneration, "Voice connection timed out. Check your network and reconnect.")
            }
        }, 60_000)
        Thread({ runTunnel(install, activeGeneration) }, "buildify-voice-tunnel").apply {
            isDaemon = true
            start()
        }
        // The Flutter bridge/token exists only in the current app process.
        return START_NOT_STICKY
    }

    private fun runTunnel(install: CloudflaredBinary.Install, activeGeneration: Int) {
        var started: Process? = null
        try {
            val builder = ProcessBuilder(
                install.binary.absolutePath, "tunnel", "--no-autoupdate",
                "--protocol", "http2", "--edge-ip-version", "4",
                "--url", "http://127.0.0.1:$PORT",
            ).directory(install.nativeDir).redirectErrorStream(true)
            val existing = System.getenv("LD_LIBRARY_PATH").orEmpty()
            builder.environment()["LD_LIBRARY_PATH"] =
                install.nativeDir.absolutePath + if (existing.isEmpty()) "" else ":$existing"
            builder.environment()["TUNNEL_DNS_RESOLVER_ADDRS"] = "1.1.1.1:53,8.8.8.8:53"
            val proc = builder.start()
            started = proc
            synchronized(processLock) {
                if (activeGeneration != generation) {
                    proc.destroy()
                    return
                }
                process = proc
            }
            val urlPattern = Regex("https://[a-z0-9-]+\\.trycloudflare\\.com")
            var discoveredUrl: String? = null
            var connected = false
            var notified = false
            proc.inputStream.bufferedReader().use { reader ->
                while (true) {
                    val line = reader.readLine() ?: break
                    if (urlPattern.containsMatchIn(line)) discoveredUrl = urlPattern.find(line)?.value
                    if (line.contains("Registered tunnel connection")) connected = true
                    if (line.contains("Unregistered tunnel connection") ||
                        line.contains("Connection terminated") ||
                        line.contains("failed to serve tunnel connection")) {
                        connected = false
                        notified = false
                        synchronized(processLock) {
                            if (activeGeneration == generation) {
                                currentStatus = "starting"
                                publicUrl = null
                            }
                        }
                    }
                    synchronized(processLock) {
                        if (activeGeneration == generation && connected && discoveredUrl != null) {
                            publicUrl = discoveredUrl
                            currentStatus = "running"
                        }
                    }
                    if (connected && discoveredUrl != null && !notified) {
                        notified = true
                        mainHandler.post {
                            if (activeGeneration == generation && currentStatus == "running") {
                                getSystemService(NotificationManager::class.java).notify(
                                    NOTIFICATION_ID, notification("Voice tools connected; open Buildify to review requests"),
                                )
                            }
                        }
                    }
                }
            }
            proc.waitFor()
            fail(activeGeneration, "Voice tunnel disconnected. Reconnect in Buildify.")
        } catch (_: Exception) {
            fail(activeGeneration, "Voice tunnel could not connect. Check your network and reconnect.")
        } finally {
            synchronized(processLock) {
                if (activeGeneration == generation) process = null
            }
            started?.destroy()
        }
    }

    private fun fail(activeGeneration: Int, message: String) {
        synchronized(processLock) {
            if (activeGeneration != generation) return
            currentStatus = "failed"
            publicUrl = null
            lastError = message
        }
        mainHandler.post { if (activeGeneration == generation) stopSelf() }
    }

    override fun onDestroy() {
        synchronized(processLock) {
            generation++
            process?.destroy()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                process?.let { if (it.isAlive) it.destroyForcibly() }
            }
            process = null
            publicUrl = null
            if (currentStatus != "failed") currentStatus = "stopped"
        }
        stopForeground(STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }

    // Android 15 limits background data-sync foreground services to six hours.
    override fun onTimeout(startId: Int, fgsType: Int) {
        currentStatus = "failed"
        lastError = "Android ended the background voice connection. Open Buildify to reconnect."
        publicUrl = null
        stopSelf()
    }

    private fun notification(text: String): Notification {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            getSystemService(NotificationManager::class.java).createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Buildify voice connection", NotificationManager.IMPORTANCE_LOW),
            )
        }
        val open = PendingIntent.getActivity(
            this, NOTIFICATION_ID, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Buildify voice")
            .setContentText(text)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(open)
            .setOngoing(true)
            .build()
    }

    companion object {
        const val PORT = 18791
        private const val ACTION_START = "com.example.buildify_flutter.action.START_VOICE_TUNNEL"
        private const val CHANNEL_ID = "buildify_voice_connection"
        private const val NOTIFICATION_ID = 1003
        @Volatile var currentStatus = "stopped"
            private set
        @Volatile var publicUrl: String? = null
            private set
        @Volatile var lastError: String? = null
            private set

        fun start(context: Context) {
            val intent = Intent(context, VoiceTunnelService::class.java).setAction(ACTION_START)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) context.startForegroundService(intent)
            else context.startService(intent)
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, VoiceTunnelService::class.java))
            currentStatus = "stopped"
            publicUrl = null
            lastError = null
        }

        fun snapshot(): Map<String, Any?> = mapOf(
            "ok" to (currentStatus != "failed"),
            "status" to currentStatus,
            "publicUrl" to publicUrl,
            "lastError" to lastError,
        )
    }
}
