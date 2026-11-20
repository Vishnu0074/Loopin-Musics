package com.example.loopin

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.media.AudioManager
import android.net.wifi.WifiManager
import android.media.audiofx.Equalizer
import android.media.audiofx.DynamicsProcessing
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.ryanheise.audioservice.AudioServiceActivity

class MainActivity : AudioServiceActivity() {
    private val audioEffectsChannel = "com.example.loopin/audio_effects"
    private val audioOutputChannel = "com.example.loopin/audio_output"
    private val originIslandChannel = "com.example.loopin/origin_island"
    private val homeWidgetsChannel = "com.example.loopin/home_widgets"
    private val syncNetworkChannel = "com.example.loopin/sync_network"
    private var syncMulticastLock: WifiManager.MulticastLock? = null
    private val notificationRequestCode = 4102
    private var equalizer: Equalizer? = null
    private var dynamics: DynamicsProcessing? = null
    private var effectSessionId: Int = 0

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, syncNetworkChannel).setMethodCallHandler { call, result ->
            when (call.method) {
                "acquireMulticastLock" -> {
                    try {
                        if (syncMulticastLock?.isHeld != true) {
                            val wifiManager = applicationContext.getSystemService(WIFI_SERVICE) as WifiManager
                            syncMulticastLock = wifiManager.createMulticastLock("loopin-sync-discovery").apply {
                                setReferenceCounted(false)
                                acquire()
                            }
                        }
                        result.success(null)
                    } catch (error: Exception) {
                        result.error("MULTICAST_LOCK", error.message, null)
                    }
                }
                "releaseMulticastLock" -> {
                    if (syncMulticastLock?.isHeld == true) syncMulticastLock?.release()
                    syncMulticastLock = null
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, audioOutputChannel).setMethodCallHandler { call, result ->
            when (call.method) {
                "getAvailableOutputs" -> {
                    val audioManager = getSystemService(AUDIO_SERVICE) as AudioManager
                    val supportedTypes = setOf(
                        android.media.AudioDeviceInfo.TYPE_BUILTIN_SPEAKER,
                        android.media.AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
                        android.media.AudioDeviceInfo.TYPE_BLE_HEADSET,
                        android.media.AudioDeviceInfo.TYPE_BLE_SPEAKER,
                    )
                    val outputs = audioManager
                        .getDevices(AudioManager.GET_DEVICES_OUTPUTS)
                        .filter { it.type in supportedTypes }
                        .mapNotNull { device ->
                            val bluetooth = device.type == android.media.AudioDeviceInfo.TYPE_BLUETOOTH_A2DP ||
                                device.type == android.media.AudioDeviceInfo.TYPE_BLE_HEADSET ||
                                device.type == android.media.AudioDeviceInfo.TYPE_BLE_SPEAKER
                            val deviceName = if (bluetooth) {
                                device.productName?.toString()?.trim()?.takeIf {
                                    it.isNotBlank() && !it.equals(Build.MODEL, ignoreCase = true)
                                } ?: "Bluetooth device"
                            } else {
                                "Phone speaker"
                            }
                            mapOf(
                                "id" to device.id,
                                "name" to deviceName,
                                "type" to outputTypeName(device.type),
                                "isBluetooth" to bluetooth
                            )
                        }
                    result.success(outputs)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, audioEffectsChannel).setMethodCallHandler { call, result ->
            when (call.method) {
                "apply" -> applyAudioEffects(call, result)
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, originIslandChannel).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestNotificationPermission" -> { requestOriginIslandNotificationPermission(); result.success(null) }
                "update" -> {
                    OriginIsland.update(
                        this,
                        call.argument<String>("mediaId").orEmpty(),
                        call.argument<String>("title").orEmpty(),
                        call.argument<String>("artist").orEmpty(),
                        null,
                        call.argument<Number>("positionMs")?.toLong() ?: 0L,
                        call.argument<Number>("durationMs")?.toLong() ?: 0L,
                        call.argument<Boolean>("isPlaying") ?: false,
                        call.argument<String>("artworkUrl").orEmpty(),
                    )
                    result.success(null)
                }
                "clear" -> { OriginIsland.clear(this); result.success(null) }
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, homeWidgetsChannel).setMethodCallHandler { call, result ->
            when (call.method) {
                "updateNowPlaying" -> {
                    val title = call.argument<String>("title") ?: "Nothing Playing"
                    val artist = call.argument<String>("artist") ?: "Tap to open Loopin"
                    val isPlaying = call.argument<Boolean>("isPlaying") ?: false
                    LoopinWidgetManager.updateNowPlaying(this, title, artist, isPlaying)
                    result.success(null)
                }
                "updateStats" -> {
                    val hours = call.argument<Number>("totalPlayedHours")?.toInt() ?: 0
                    val mins = call.argument<Number>("dailyMinutes")?.toInt() ?: 0
                    val streak = call.argument<Number>("listeningStreakDays")?.toInt() ?: 0
                    val topTrack = call.argument<String>("topTrack") ?: "Keep listening on Loopin"
                    val topPlays = call.argument<String>("topPlays") ?: "★"
                    LoopinWidgetManager.updateStats(this, hours, mins, streak, topTrack, topPlays)
                    result.success(null)
                }
                "updateLyrics" -> {
                    val song = call.argument<String>("song") ?: "No Song Playing"
                    val text = call.argument<String>("text") ?: "Play a song with lyrics to see live verses right on your home screen."
                    LoopinWidgetManager.updateLyrics(this, song, text)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun outputTypeName(type: Int): String = when (type) {
        android.media.AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> "Phone speaker"
        android.media.AudioDeviceInfo.TYPE_BUILTIN_EARPIECE -> "Earpiece"
        android.media.AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
        android.media.AudioDeviceInfo.TYPE_WIRED_HEADSET -> "Wired headphones"
        android.media.AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
        android.media.AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> "Bluetooth audio"
        android.media.AudioDeviceInfo.TYPE_BLE_HEADSET,
        android.media.AudioDeviceInfo.TYPE_BLE_SPEAKER -> "Bluetooth LE audio"
        android.media.AudioDeviceInfo.TYPE_USB_HEADSET -> "USB headset"
        android.media.AudioDeviceInfo.TYPE_HDMI,
        android.media.AudioDeviceInfo.TYPE_HDMI_ARC,
        android.media.AudioDeviceInfo.TYPE_HDMI_EARC -> "HDMI audio"
        else -> "Audio output"
    }

    private fun applyAudioEffects(call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result) {
        val sessionId = call.argument<Int>("sessionId") ?: 0
        if (sessionId <= 0) { result.error("SESSION", "Invalid audio session", null); return }
        try {
            if (effectSessionId != sessionId) {
                equalizer?.release()
                dynamics?.release()
                equalizer = Equalizer(0, sessionId)
                effectSessionId = sessionId
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    val builder = DynamicsProcessing.Config.Builder(
                        DynamicsProcessing.VARIANT_FAVOR_FREQUENCY_RESOLUTION,
                        2,
                        false,
                        0,
                        false,
                        0,
                        false,
                        0,
                        false
                    )
                    dynamics = DynamicsProcessing(0, sessionId, builder.build())
                    dynamics?.enabled = true
                }
            }
            equalizer?.let { eq ->
                val enabled = call.argument<Boolean>("equalizerEnabled") ?: false
                eq.enabled = enabled
                if (enabled) {
                    val bands = call.argument<Map<String, Any>>("bands") ?: emptyMap()
                    val range = eq.bandLevelRange
                    for (i in 0 until eq.numberOfBands.toInt()) {
                        val freq = eq.getCenterFreq(i.toShort()).toDouble() / 1000.0
                        val key = bands.keys.minByOrNull { kotlin.math.abs((it.toDoubleOrNull() ?: freq) - freq) }
                        val gain = if (key == null) 0.0 else (bands[key] as? Number)?.toDouble() ?: 0.0
                        val clamped = gain.coerceIn(range[0].toDouble() / 100.0, range[1].toDouble() / 100.0)
                        eq.setBandLevel(i.toShort(), (clamped * 100).toInt().toShort())
                    }
                }
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                val d = dynamics
                if (d != null) {
                    val balance = (call.argument<Number>("balance")?.toDouble() ?: 0.0).coerceIn(-1.0, 1.0)
                    val leftDb = when {
                        balance <= 0.0 -> 0.0f
                        balance >= 0.98 -> -90.0f
                        else -> (20.0 * kotlin.math.log10(1.0 - balance)).toFloat().coerceIn(-90.0f, 0.0f)
                    }
                    val rightDb = when {
                        balance >= 0.0 -> 0.0f
                        balance <= -0.98 -> -90.0f
                        else -> (20.0 * kotlin.math.log10(1.0 + balance)).toFloat().coerceIn(-90.0f, 0.0f)
                    }
                    d.setInputGainbyChannel(0, leftDb)
                    d.setInputGainbyChannel(1, rightDb)
                    d.enabled = true
                }
            }
            result.success(null)
        } catch (e: Exception) {
            result.error("AUDIO_EFFECT", e.message, null)
        }
    }

    private fun requestOriginIslandNotificationPermission() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        if (!isVivoDevice()) return
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) return
        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), notificationRequestCode)
    }

    override fun onDestroy() {
        // When the user explicitly closes the app/task, end the vendor island
        // session. Do not clear it for ordinary backgrounding or configuration
        // changes, where isFinishing is false.
        if (isFinishing) OriginIsland.clear(applicationContext)
        equalizer?.release()
        dynamics?.release()
        if (syncMulticastLock?.isHeld == true) syncMulticastLock?.release()
        syncMulticastLock = null
        equalizer = null
        dynamics = null
        super.onDestroy()
    }

    private fun isVivoDevice(): Boolean {
        val brand = Build.BRAND.orEmpty()
        val manufacturer = Build.MANUFACTURER.orEmpty()
        return brand.contains("vivo", ignoreCase = true) ||
            brand.contains("iqoo", ignoreCase = true) ||
            manufacturer.contains("vivo", ignoreCase = true)
    }
}