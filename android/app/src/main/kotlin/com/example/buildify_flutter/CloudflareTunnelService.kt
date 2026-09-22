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
import android.os.HandlerThread
import android.os.IBinder
import android.os.Looper
import android.util.Log
import androidx.core.app.NotificationCompat
import java.io.BufferedReader
import java.io.InputStreamReader
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

class CloudflareTunnelService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    private var tunnelProcess: Process? = null
    private val processLock = Any()
    private var logThread: Thread? = null
    private var idleHandler: Handler? = null
    private var idleHandlerThread: HandlerThread? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val localPort = intent.getIntExtra(EXTRA_PORT, 8080)
                val tunnelUrl = intent.getStringExtra(EXTRA_TUNNEL_URL)

                cleanup()
                startForeground(NOTIFICATION_ID, createNotification("Starting tunnel on port $localPort"))

                val install = CloudflaredBinary.prepare(this)
                if (install == null) {
                    currentStatus = TunnelStatus.FAILED
                    lastError = "cloudflared binary not found"
                    lastPublicUrl = null
                    stopSelf()
                    return START_NOT_STICKY
                }

                currentStatus = TunnelStatus.STARTING
                lastError = null
                lastPublicUrl = null

                executor.execute { runCloudflared(install, localPort, tunnelUrl) }
            }

            ACTION_STOP -> {
                cleanup()
                currentStatus = TunnelStatus.STOPPED
                lastPublicUrl = null
                stopSelf()
            }
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        cleanup()
        currentStatus = TunnelStatus.STOPPED
        lastPublicUrl = null
        super.onDestroy()
    }

    private fun runCloudflared(install: CloudflaredBinary.Install, port: Int, tunnelUrl: String?) {
        // Create a custom resolv.conf so Go's net package uses real DNS servers
        // instead of [::1]:53 which doesn't work on Android
        val resolvConf = java.io.File(applicationContext.filesDir, "resolv.conf")
        try {
            resolvConf.writeText("nameserver 1.1.1.1\nnameserver 8.8.8.8\n")
            Log.i(TAG, "Wrote resolv.conf to ${resolvConf.absolutePath}")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to write resolv.conf", e)
        }

        val args = mutableListOf(
            install.binary.absolutePath,
            "tunnel",
            "--edge-ip-version", "4",
            "--protocol", "quic",
            "--url",
            "http://localhost:$port",
        )
        if (tunnelUrl != null) {
            args.addAll(listOf("--hostname", tunnelUrl))
        }

        try {
            val pb = ProcessBuilder(args)
            pb.directory(install.nativeDir)
            val existingPath = System.getenv("LD_LIBRARY_PATH").orEmpty()
            pb.environment()["LD_LIBRARY_PATH"] = if (existingPath.isEmpty()) {
                install.nativeDir.absolutePath
            } else {
                "${install.nativeDir.absolutePath}:$existingPath"
            }
            // Force Go's DNS resolver to use our custom resolv.conf with real DNS servers
            pb.environment()["GODEBUG"] = "netdns=go"
            pb.environment()["RES_OPTIONS"] = "use-vc"
            pb.environment()["TUNNEL_DNS_RESOLVER_ADDRS"] = "1.1.1.1:53,8.8.8.8:53"
            // Point Go to our custom resolv.conf
            pb.environment()["RESOLV_CONF"] = resolvConf.absolutePath
            pb.redirectErrorStream(true)

            val proc = try {
                pb.start()
            } catch (e: Exception) {
                Log.e(TAG, "Failed to start cloudflared process", e)
                currentStatus = TunnelStatus.FAILED
                lastError = e.message ?: "failed to start cloudflared"
                stopForegroundAndSelf()
                return
            }

            synchronized(processLock) { tunnelProcess = proc }
            currentStatus = TunnelStatus.STARTING

            val reader = BufferedReader(InputStreamReader(proc.inputStream))
            val urlPattern = Regex("""https://[a-zA-Z0-9.-]+\.trycloudflare\.com""")

            logThread = Thread {
                try {
                    var line: String?
                    while (reader.readLine().also { line = it } != null) {
                        val l = line ?: continue
                        Log.i(TAG, l)
                        val match = urlPattern.find(l)
                        if (match != null && lastPublicUrl == null) {
                            lastPublicUrl = match.value
                            currentStatus = TunnelStatus.RUNNING
                            mainHandler.post {
                                val nm = getSystemService(NotificationManager::class.java)
                                nm.notify(NOTIFICATION_ID, createNotification("Tunnel active: ${match.value}"))
                            }
                        }
                    }
                } catch (_: Exception) {
                }
            }.also { it.isDaemon = true; it.start() }

            val exitCode = proc.waitFor()
            logThread?.join(2000)

            if (exitCode != 0 && lastError == null) {
                lastError = if (lastPublicUrl != null) {
                    "tunnel disconnected (exit $exitCode). If DNS errors persist, turn off Android Private DNS in system settings."
                } else {
                    "cloudflared exited with code $exitCode"
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "runCloudflared failed", e)
            lastError = e.message ?: "tunnel error"
        } finally {
            synchronized(processLock) { tunnelProcess = null }
            if (currentStatus != TunnelStatus.STOPPED) {
                currentStatus = TunnelStatus.FAILED
            }
            stopForegroundAndSelf()
        }
    }

    private fun cleanup() {
        synchronized(processLock) {
            tunnelProcess?.let { proc ->
                proc.destroy()
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    if (proc.isAlive) proc.destroyForcibly()
                }
            }
            tunnelProcess = null
        }
        logThread?.interrupt()
        logThread = null
    }

    private fun createNotification(text: String): Notification {
        createNotificationChannel()
        val openAppIntent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, openAppIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Buildify Tunnel")
            .setContentText(text)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Buildify Cloudflare Tunnel",
            NotificationManager.IMPORTANCE_LOW,
        )
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    private fun stopForegroundAndSelf() {
        mainHandler.post {
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    stopForeground(STOP_FOREGROUND_REMOVE)
                } else {
                    @Suppress("DEPRECATION")
                    stopForeground(true)
                }
            } catch (_: Exception) {}
            try { stopSelf() } catch (_: Exception) {}
        }
    }

    companion object {
        private const val TAG = "CloudflareTunnelService"
        private const val CHANNEL_ID = "buildify_tunnel_channel"
        private const val NOTIFICATION_ID = 1002
        private const val ACTION_START = "com.example.buildify_flutter.action.START_TUNNEL"
        private const val ACTION_STOP = "com.example.buildify_flutter.action.STOP_TUNNEL"
        private const val EXTRA_PORT = "port"
        private const val EXTRA_TUNNEL_URL = "tunnelUrl"

        private val executor = Executors.newSingleThreadExecutor()
        private val mainHandler = Handler(Looper.getMainLooper())
        private val autoStopTriggered = AtomicBoolean(false)

        @Volatile
        var currentStatus: TunnelStatus = TunnelStatus.STOPPED
            internal set

        @Volatile
        var lastError: String? = null
            internal set

        @Volatile
        var lastPublicUrl: String? = null
            internal set

        fun startTunnel(context: Context, port: Int, tunnelUrl: String? = null) {
            autoStopTriggered.set(false)
            val intent = Intent(context, CloudflareTunnelService::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_PORT, port)
                if (tunnelUrl != null) putExtra(EXTRA_TUNNEL_URL, tunnelUrl)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stopTunnel(context: Context) {
            val intent = Intent(context, CloudflareTunnelService::class.java).apply {
                action = ACTION_STOP
            }
            context.startService(intent)
        }
    }
}

enum class TunnelStatus {
    STOPPED,
    STARTING,
    RUNNING,
    FAILED,
}