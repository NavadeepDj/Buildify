package com.example.buildify_flutter

import android.app.ActivityManager
import android.content.Intent
import android.content.IntentFilter
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Environment
import android.os.StatFs
import android.text.format.Formatter
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.net.Inet4Address
import java.net.NetworkInterface

class MainActivity : FlutterActivity() {
    private val channelName = "buildify.ai/server"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getGatewayConnectorToken" -> result.success(BuildConfig.CF_TUNNEL_TOKEN)
                    "startServer" -> {
                        val modelPath = call.argument<String>("modelPath")
                        val port = call.argument<Int>("port") ?: 8080
                        val apiKey = call.argument<String>("apiKey")
                        val idleMinutes = call.argument<Int>("idleMinutes") ?: 0
                        val batteryStopPct = call.argument<Int>("batteryStopPct") ?: 0
                        val thermalStop = call.argument<Boolean>("thermalStop") ?: true
                        if (modelPath.isNullOrBlank()) {
                            result.error("INVALID_ARGS", "modelPath is required", null)
                            return@setMethodCallHandler
                        }
                        AiServerService.startService(
                            this,
                            modelPath,
                            port,
                            apiKey = apiKey,
                            idleMinutes = idleMinutes,
                            batteryStopPct = batteryStopPct,
                            thermalStop = thermalStop,
                        )
                        result.success(
                            mapOf(
                                "ok" to true,
                                "status" to AiServerService.currentStatus.name.lowercase(),
                                "port" to AiServerService.currentPort,
                            ),
                        )
                    }

                    "stopServer" -> {
                        AiServerService.stopService(this)
                        result.success(
                            mapOf(
                                "ok" to true,
                                "status" to AiServerService.currentStatus.name.lowercase(),
                            ),
                        )
                    }

                    "getServerStatus" -> {
                        result.success(
                            mapOf(
                                "status" to AiServerService.currentStatus.name.lowercase(),
                                "port" to AiServerService.currentPort,
                                "modelPath" to AiServerService.currentModelPath,
                                "lastError" to AiServerService.lastError,
                                "stopReason" to AiServerService.stopReason,
                            ),
                        )
                    }

                    "getModelBasePath" -> {
                        val dir = File(applicationContext.filesDir, "models")
                        dir.mkdirs()
                        result.success(dir.absolutePath)
                    }

                    "getLocalIp" -> {
                        result.success(getLocalIpAddress())
                    }

                    "getTailscaleIp" -> {
                        result.success(getTailscaleIpAddress())
                    }

                    "startTunnel" -> {
                        val port = call.argument<Int>("port") ?: 8080
                        val tunnelUrl = call.argument<String>("tunnelUrl")
                        val token = call.argument<String>("tunnelToken")
                        val active = CloudflareTunnelService.currentStatus == TunnelStatus.RUNNING ||
                            CloudflareTunnelService.currentStatus == TunnelStatus.STARTING
                        if (active) {
                            val sameMode = CloudflareTunnelService.isGateway == !token.isNullOrBlank()
                            result.success(mapOf("ok" to sameMode,
                                "status" to CloudflareTunnelService.currentStatus.name.lowercase(),
                                "message" to if (sameMode) null else "Stop the active tunnel before switching tunnel modes."))
                            return@setMethodCallHandler
                        }
                        CloudflareTunnelService.startTunnel(this, port, tunnelUrl, token)
                        result.success(
                            mapOf(
                                "ok" to true,
                                "status" to CloudflareTunnelService.currentStatus.name.lowercase(),
                            ),
                        )
                    }

                    "stopTunnel" -> {
                        CloudflareTunnelService.stopTunnel(this)
                        result.success(
                            mapOf(
                                "ok" to true,
                                "status" to CloudflareTunnelService.currentStatus.name.lowercase(),
                            ),
                        )
                    }

                    "getTunnelStatus" -> {
                        result.success(
                            mapOf(
                                "status" to CloudflareTunnelService.currentStatus.name.lowercase(),
                                "publicUrl" to CloudflareTunnelService.lastPublicUrl,
                                "isGateway" to CloudflareTunnelService.isGateway,
                                "lastError" to CloudflareTunnelService.lastError,
                            ),
                        )
                    }

                    "getDeviceMetrics" -> {
                        result.success(getDeviceMetrics())
                    }

                    else -> result.notImplemented()
                }
            }
    }

    private fun getLocalIpAddress(): String {
        NetworkInterface.getNetworkInterfaces()?.toList()?.forEach { intf ->
            intf.inetAddresses.toList().forEach { address ->
                if (!address.isLoopbackAddress && address is Inet4Address) {
                    val name = intf.name.lowercase()
                    if (name != "tailscale0" && name != "wg0") {
                        return address.hostAddress ?: "0.0.0.0"
                    }
                }
            }
        }

        val wifi = applicationContext.getSystemService(WIFI_SERVICE) as? WifiManager
        val ip = wifi?.connectionInfo?.ipAddress ?: 0
        return if (ip != 0) Formatter.formatIpAddress(ip) else "0.0.0.0"
    }

    private fun getTailscaleIpAddress(): String? {
        NetworkInterface.getNetworkInterfaces()?.toList()?.forEach { intf ->
            val name = intf.name.lowercase()
            if (name == "tailscale0" || name == "wg0" || name.startsWith("ts") && name.length <= 5) {
                intf.inetAddresses.toList().forEach { address ->
                    if (!address.isLoopbackAddress && address is Inet4Address) {
                        return address.hostAddress
                    }
                }
            }
        }
        // Fallback: look for any 100.x.x.x address (Tailscale CGNAT range)
        NetworkInterface.getNetworkInterfaces()?.toList()?.forEach { intf ->
            intf.inetAddresses.toList().forEach { address ->
                if (!address.isLoopbackAddress && address is Inet4Address) {
                    val ip = address.hostAddress ?: return@forEach
                    if (ip.startsWith("100.")) {
                        return ip
                    }
                }
            }
        }
        return null
    }

    private fun getDeviceMetrics(): Map<String, Any> {
        val am = applicationContext.getSystemService(ACTIVITY_SERVICE) as ActivityManager
        val memInfo = ActivityManager.MemoryInfo()
        am.getMemoryInfo(memInfo)
        val totalMemGb = memInfo.totalMem / (1024 * 1024 * 1024)
        val availMemGb = memInfo.availMem.toDouble() / (1024 * 1024 * 1024)

        val dataDir = Environment.getDataDirectory()
        val stat = StatFs(dataDir.path)
        val freeStorageGb = (stat.availableBlocksLong * stat.blockSizeLong).toDouble() / (1024 * 1024 * 1024)

        val batteryIntent = applicationContext.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val batteryPercent = batteryIntent?.let {
            val level = it.getIntExtra(android.os.BatteryManager.EXTRA_LEVEL, -1)
            val scale = it.getIntExtra(android.os.BatteryManager.EXTRA_SCALE, -1)
            if (level >= 0 && scale > 0) (level * 100) / scale else 0
        } ?: 0
        val batteryCharging = batteryIntent?.let {
            val status = it.getIntExtra(android.os.BatteryManager.EXTRA_STATUS, -1)
            status == android.os.BatteryManager.BATTERY_STATUS_CHARGING ||
                status == android.os.BatteryManager.BATTERY_STATUS_FULL
        } ?: false

        val cpuCores = Runtime.getRuntime().availableProcessors()
        val cpuLabel = "${cpuCores}-core ARM"

        return mapOf(
            "ramGb" to totalMemGb.toInt(),
            "availRamGb" to (Math.round(availMemGb * 10.0) / 10.0),
            "freeStorageGb" to (Math.round(freeStorageGb * 10.0) / 10.0),
            "batteryPercent" to batteryPercent,
            "batteryCharging" to batteryCharging,
            "cpuLabel" to cpuLabel,
        )
    }
}
