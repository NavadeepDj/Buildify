package com.example.buildify_flutter

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

class AiServerService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    private var batteryReceiver: BroadcastReceiver? = null
    private var thermalListener: PowerManager.OnThermalStatusChangedListener? = null
    private var idleHandler: Handler? = null
    private var idleHandlerThread: HandlerThread? = null
    private val idleCheck = Runnable { checkIdle() }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val modelPath = intent.getStringExtra(EXTRA_MODEL_PATH) ?: return START_NOT_STICKY
                val port = intent.getIntExtra(EXTRA_PORT, 8080)
                val apiKey = intent.getStringExtra(EXTRA_API_KEY)
                val idleMinutes = intent.getIntExtra(EXTRA_IDLE_MINUTES, 0)
                val batteryStop = intent.getIntExtra(EXTRA_BATTERY_STOP_PCT, 0)
                val thermalStop = intent.getBooleanExtra(EXTRA_THERMAL_STOP, true)
                val contextTokens = intent.getIntExtra("contextTokens", 0)

                cleanupScheduled.set(false)
                killServerProcess()
                currentModelPath = modelPath
                currentPort = port
                currentApiKeyHash = apiKey?.takeIf { it.isNotBlank() }?.let { hashApiKey(it) }
                currentIdleMinutes = idleMinutes
                currentBatteryStop = batteryStop
                currentThermalStop = thermalStop
                lastError = null
                stopReason = null
                lastRequestEpochMillis.set(System.currentTimeMillis())
                currentStatus = ServerStatus.STARTING

                startForeground(NOTIFICATION_ID, createNotification(port, ServerStatus.STARTING))
                registerSafetyHooks()
                executor.execute { runLlamaServer(modelPath, port, apiKey, contextTokens) }
            }

            ACTION_STOP -> {
                stopReason = stopReason ?: "user stopped"
                killServerProcess()
                currentStatus = ServerStatus.STOPPED
                unregisterSafetyHooks()
                scheduleServiceStop(this)
            }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        killServerProcess()
        unregisterSafetyHooks()
        currentStatus = ServerStatus.STOPPED
        executor.shutdownNow()
        super.onDestroy()
    }

    private fun runLlamaServer(modelPath: String, port: Int, apiKey: String?, contextTokens: Int) {
        try {
            val install =
                LlamaServerBinary.prepare(this)
                    ?: run {
                        lastError =
                            "Missing llama-server binary. Add jniLibs/<abi>/libllama-server.so (see jniLibs/arm64-v8a/README.txt)."
                        currentStatus = ServerStatus.STOPPED
                        return@runLlamaServer
                    }

            val model = File(modelPath)
            if (!model.exists()) {
                lastError = "Model missing: $modelPath"
                currentStatus = ServerStatus.STOPPED
                return@runLlamaServer
            }

            val cacheDir = File(cacheDir, "llama_cache").apply { mkdirs() }
            val args = mutableListOf(
                install.binary.absolutePath,
                "-m", model.absolutePath,
                "--host", "0.0.0.0",
                "--port", port.toString(),
            )
            if (!apiKey.isNullOrBlank()) {
                args += "--api-key"
                args += apiKey
            }
            if (contextTokens in 128..8192) {
                args += "--ctx-size"
                args += contextTokens.toString()
            }
            val pb = ProcessBuilder(args)
            pb.directory(install.nativeDir)
            val existingLdPath = System.getenv("LD_LIBRARY_PATH").orEmpty()
            val ldPath =
                if (existingLdPath.isEmpty()) {
                    install.nativeDir.absolutePath
                } else {
                    "${install.nativeDir.absolutePath}:$existingLdPath"
                }
            pb.environment()["LD_LIBRARY_PATH"] = ldPath
            pb.environment()["TMPDIR"] = cacheDir.absolutePath
            pb.redirectErrorStream(true)

            val proc =
                try {
                    pb.start()
                } catch (e: Exception) {
                    Log.e(TAG, "ProcessBuilder.start failed", e)
                    lastError = e.message ?: "failed to start llama-server"
                    currentStatus = ServerStatus.STOPPED
                    return@runLlamaServer
                }

            synchronized(processLock) {
                serverProcess = proc
            }
            currentStatus = ServerStatus.RUNNING
            mainHandler.post {
                val nm = getSystemService(NotificationManager::class.java)
                nm.notify(NOTIFICATION_ID, createNotification(port, ServerStatus.RUNNING))
            }

            val drain =
                Thread {
                    try {
                        proc.inputStream.bufferedReader().forEachLine { line ->
                            // Track real activity for idle timeout. llama-server prints
                            // "log_server_r: done request: ..." per HTTP request.
                            if (line.contains("log_server_r: done request") ||
                                line.contains("HTTP/1.1\" 200")
                            ) {
                                lastRequestEpochMillis.set(System.currentTimeMillis())
                            }
                            Log.i(TAG, line)
                        }
                    } catch (_: Exception) {
                    }
                }
            drain.isDaemon = true
            drain.start()

            val exit = proc.waitFor()
            try {
                drain.join(1500)
            } catch (_: InterruptedException) {
            }

            if (exit != 0 && lastError == null) {
                lastError = "llama-server exited with code $exit"
            }
        } catch (e: Exception) {
            Log.e(TAG, "runLlamaServer failed", e)
            if (lastError == null) {
                lastError = e.message ?: "server error"
            }
        } finally {
            synchronized(processLock) {
                serverProcess = null
            }
            currentStatus = ServerStatus.STOPPED
            unregisterSafetyHooks()
            scheduleServiceStop(this@AiServerService)
        }
    }

    // ---- Safety hooks --------------------------------------------------

    private fun registerSafetyHooks() {
        // Battery monitor (also fires once with sticky intent).
        if (currentBatteryStop > 0 && batteryReceiver == null) {
            val receiver =
                object : BroadcastReceiver() {
                    override fun onReceive(context: Context?, intent: Intent?) {
                        val level = intent?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
                        val scale = intent?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
                        val pluggedRaw = intent?.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0) ?: 0
                        val charging = pluggedRaw != 0
                        if (level <= 0 || scale <= 0) return
                        val pct = (level * 100) / scale
                        if (!charging && pct <= currentBatteryStop) {
                            triggerAutoStop("battery $pct% (limit $currentBatteryStop%)")
                        }
                    }
                }
            try {
                registerReceiver(receiver, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
                batteryReceiver = receiver
            } catch (e: Exception) {
                Log.w(TAG, "battery receiver register failed", e)
            }
        }

        // Thermal listener (API 29+).
        if (currentThermalStop && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val pm = getSystemService(POWER_SERVICE) as? PowerManager
            if (pm != null && thermalListener == null) {
                val listener =
                    PowerManager.OnThermalStatusChangedListener { status ->
                        if (status >= PowerManager.THERMAL_STATUS_SEVERE) {
                            triggerAutoStop("thermal status $status (severe or higher)")
                        }
                    }
                try {
                    pm.addThermalStatusListener(listener)
                    thermalListener = listener
                } catch (e: Exception) {
                    Log.w(TAG, "thermal listener register failed", e)
                }
            }
        }

        // Idle timer.
        if (currentIdleMinutes > 0 && idleHandlerThread == null) {
            val ht = HandlerThread("ai-idle-watch").apply { start() }
            idleHandlerThread = ht
            val handler = Handler(ht.looper)
            idleHandler = handler
            handler.postDelayed(idleCheck, IDLE_CHECK_INTERVAL_MS)
        }
    }

    private fun unregisterSafetyHooks() {
        batteryReceiver?.let {
            try {
                unregisterReceiver(it)
            } catch (_: Exception) {
            }
        }
        batteryReceiver = null

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            thermalListener?.let { l ->
                val pm = getSystemService(POWER_SERVICE) as? PowerManager
                try {
                    pm?.removeThermalStatusListener(l)
                } catch (_: Exception) {
                }
            }
        }
        thermalListener = null

        idleHandler?.removeCallbacksAndMessages(null)
        idleHandler = null
        idleHandlerThread?.quitSafely()
        idleHandlerThread = null
    }

    private fun checkIdle() {
        if (currentStatus != ServerStatus.RUNNING) return
        val limitMinutes = currentIdleMinutes
        if (limitMinutes <= 0) return
        val idleMs = System.currentTimeMillis() - lastRequestEpochMillis.get()
        if (idleMs >= limitMinutes * 60_000L) {
            triggerAutoStop("idle for ${idleMs / 60_000L} min (limit $limitMinutes min)")
            return
        }
        idleHandler?.postDelayed(idleCheck, IDLE_CHECK_INTERVAL_MS)
    }

    private fun triggerAutoStop(reason: String) {
        if (autoStopTriggered.compareAndSet(false, true)) {
            stopReason = reason
            lastError = "auto-stop: $reason"
            Log.w(TAG, "auto-stop: $reason")
            mainHandler.post {
                try {
                    val nm = getSystemService(NotificationManager::class.java)
                    nm.notify(
                        NOTIFICATION_ID,
                        createNotification(currentPort, ServerStatus.STOPPING, "Auto-stop: $reason"),
                    )
                } catch (_: Exception) {
                }
            }
            killServerProcess()
        }
    }

    // ---- Notification --------------------------------------------------

    private fun createNotification(
        port: Int,
        status: ServerStatus,
        overrideText: String? = null,
    ): Notification {
        createNotificationChannel()
        val openAppIntent = Intent(this, MainActivity::class.java)
        val pendingIntent =
            PendingIntent.getActivity(
                this,
                0,
                openAppIntent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
        val (title, text) =
            when (status) {
                ServerStatus.STARTING -> "AI Server Starting" to "Port $port"
                ServerStatus.RUNNING -> "AI Server Running" to "Port $port · 0.0.0.0"
                else -> "AI Server" to "Port $port"
            }
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(overrideText ?: text)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(pendingIntent)
            .setOngoing(status == ServerStatus.RUNNING || status == ServerStatus.STARTING)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel =
            NotificationChannel(
                CHANNEL_ID,
                "Buildify AI Server",
                NotificationManager.IMPORTANCE_LOW,
            )
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(channel)
    }

    companion object {
        private const val TAG = "AiServerService"
        private const val ACTION_START = "com.example.buildify_flutter.action.START_AI_SERVER"
        private const val ACTION_STOP = "com.example.buildify_flutter.action.STOP_AI_SERVER"
        private const val EXTRA_MODEL_PATH = "modelPath"
        private const val EXTRA_PORT = "port"
        private const val EXTRA_API_KEY = "apiKey"
        private const val EXTRA_IDLE_MINUTES = "idleMinutes"
        private const val EXTRA_BATTERY_STOP_PCT = "batteryStopPct"
        private const val EXTRA_THERMAL_STOP = "thermalStop"
        private const val CHANNEL_ID = "buildify_ai_server_channel"
        private const val NOTIFICATION_ID = 1001
        private const val IDLE_CHECK_INTERVAL_MS = 30_000L

        private val executor = Executors.newSingleThreadExecutor()
        private val processLock = Any()
        private var serverProcess: Process? = null

        private val cleanupScheduled = AtomicBoolean(false)
        private val autoStopTriggered = AtomicBoolean(false)
        private val lastRequestEpochMillis = AtomicLong(0L)

        @Volatile
        var currentStatus: ServerStatus = ServerStatus.STOPPED
            internal set

        @Volatile
        var currentPort: Int = 8080
            internal set

        @Volatile
        var currentModelPath: String? = null
            internal set

        @Volatile
        var lastError: String? = null
            internal set

        @Volatile
        var stopReason: String? = null
            internal set

        // For status reporting only — never expose the raw key.
        @Volatile
        var currentApiKeyHash: String? = null
            internal set

        @Volatile
        var currentIdleMinutes: Int = 0
            internal set

        @Volatile
        var currentBatteryStop: Int = 0
            internal set

        @Volatile
        var currentThermalStop: Boolean = true
            internal set

        private val mainHandler = Handler(Looper.getMainLooper())

        fun startService(
            context: Context,
            modelPath: String,
            port: Int,
            apiKey: String? = null,
            idleMinutes: Int = 0,
            batteryStopPct: Int = 0,
            thermalStop: Boolean = true,
            contextTokens: Int = 0,
        ) {
            autoStopTriggered.set(false)
            val intent =
                Intent(context, AiServerService::class.java).apply {
                    action = ACTION_START
                    putExtra(EXTRA_MODEL_PATH, modelPath)
                    putExtra(EXTRA_PORT, port)
                    if (!apiKey.isNullOrBlank()) putExtra(EXTRA_API_KEY, apiKey)
                    putExtra(EXTRA_IDLE_MINUTES, idleMinutes)
                    putExtra(EXTRA_BATTERY_STOP_PCT, batteryStopPct)
                    putExtra(EXTRA_THERMAL_STOP, thermalStop)
                    putExtra("contextTokens", contextTokens)
                }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stopService(context: Context) {
            val intent =
                Intent(context, AiServerService::class.java).apply {
                    action = ACTION_STOP
                }
            context.startService(intent)
        }

        fun killServerProcess() {
            synchronized(processLock) {
                serverProcess?.let { proc ->
                    proc.destroy()
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        if (proc.isAlive) {
                            proc.destroyForcibly()
                        }
                    }
                }
                serverProcess = null
            }
        }

        private fun scheduleServiceStop(service: Service) {
            if (!cleanupScheduled.compareAndSet(false, true)) return
            mainHandler.post {
                try {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                        service.stopForeground(Service.STOP_FOREGROUND_REMOVE)
                    } else {
                        @Suppress("DEPRECATION")
                        service.stopForeground(true)
                    }
                } catch (_: Exception) {
                }
                try {
                    service.stopSelf()
                } catch (_: Exception) {
                }
            }
        }

        private fun hashApiKey(raw: String): String {
            // Cheap fingerprint, just so the UI can show "key fingerprint: abc1…" if wanted.
            var h = 0
            for (c in raw) h = (h * 31 + c.code) and 0x7fffffff
            return "%08x".format(h)
        }
    }
}

enum class ServerStatus {
    STOPPED,
    STARTING,
    RUNNING,
    STOPPING,
}
