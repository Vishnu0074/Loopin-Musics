package com.example.loopin

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.app.PendingIntent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.LruCache
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors
import java.util.concurrent.ConcurrentHashMap
import android.graphics.drawable.Icon
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper

/**
 * Vivo/iQOO OriginOS 6 Super Island notification adapter.
 *
 * OriginOS 6 dynamically renders Super Island UI from structured
 * notification.superx.* bundles. Unsupported Vivo firmware is intentionally
 * ignored so Loopin does not leave a duplicate silent notification in the shade.
 */
object OriginIsland {
    private const val CHANNEL_ID = "loopin_origin_island_v2"
    private const val NOTIFICATION_TAG = "VIVO_SUPERX_TAG"
    private const val NOTIFICATION_ID = 3001
    private const val SCENE = "TRAIN"
    private const val OP_SHOW = 0
    private const val OP_UPDATE = 1
    private const val OP_END = 2
    private var islandPosted = false
    private var clearGeneration = 0
    private const val ACCENT_COLOR = 0xFF80CBC4.toInt()
    private val artworkExecutor = Executors.newSingleThreadExecutor()
    private val pendingArtwork = ConcurrentHashMap.newKeySet<String>()
    private val artworkCache = object : LruCache<String, Bitmap>(16 * 1024) {
        override fun sizeOf(key: String, value: Bitmap): Int = value.byteCount / 1024
    }
    @Volatile private var latestMediaId: String = ""

    fun update(
        context: Context,
        mediaId: String = "",
        title: String,
        artist: String,
        artwork: Bitmap? = null,
        positionMs: Long,
        durationMs: Long,
        isPlaying: Boolean,
        artworkUrl: String = "",
    ) {
        if (!isVivoDevice()) return
        if (!isOriginIslandAvailable(context)) {
            clear(context)
            return
        }

        runCatching {
            clearGeneration++ // Invalidate any delayed cancellation from an earlier session.
            latestMediaId = mediaId
            val manager = context.getSystemService(NotificationManager::class.java) ?: return
            ensureChannel(manager)
            registerScene(manager, context)

            val resolvedArtwork = artwork ?: artworkUrl.takeIf { it.isNotBlank() }?.let {
                artworkCache.get(it)
            }
            if (resolvedArtwork == null && artworkUrl.isNotBlank()) {
                loadArtwork(context.applicationContext, mediaId, title, artist, artworkUrl,
                    positionMs, durationMs, isPlaying)
            }

            val notification = buildMusicNotification(
                context = context,
                mediaId = mediaId,
                title = title,
                artist = artist,
                artwork = resolvedArtwork,
                positionMs = positionMs,
                durationMs = durationMs,
                isPlaying = isPlaying,
            )
            manager.notify(NOTIFICATION_TAG, NOTIFICATION_ID, notification)
            islandPosted = true
        }
    }

    fun clear(context: Context) {
        if (!isVivoDevice()) return

        runCatching {
            latestMediaId = ""
            val manager = context.getSystemService(NotificationManager::class.java) ?: return
            ensureChannel(manager)

            // Always send END. This state is intentionally not gated by the
            // process-local islandPosted flag: Android may recreate the process
            // after the vendor UI has retained an older SuperX session.
            val generation = ++clearGeneration
            val endNotification = Notification.Builder(context, CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_media_play)
                .setOngoing(false)
                .setOnlyAlertOnce(true)
                .setExtras(Bundle().apply {
                    putInt("notification.superx.operation", OP_END)
                    putBoolean("notification.superx.showNotify", false)
                    putString("notification.superx.scene", SCENE)
                    putInt("notification.superx.changedRecord", Int.MAX_VALUE)
                })
                .build()

            // Let OriginOS consume the END operation before removing its
            // transport notification. Do not cancel untagged media notifications.
            manager.notify(NOTIFICATION_TAG, NOTIFICATION_ID, endNotification)
            islandPosted = false
            Handler(Looper.getMainLooper()).postDelayed({
                if (generation == clearGeneration) {
                    manager.cancel(NOTIFICATION_TAG, NOTIFICATION_ID)
                }
            }, 900L)
        }
    }


    /**
     * Load remote album artwork off the main thread. OriginOS receives the
     * real cover as soon as it is available; repeated progress updates reuse
     * the in-memory bitmap instead of downloading it again.
     */
    private fun loadArtwork(
        context: Context,
        mediaId: String,
        title: String,
        artist: String,
        artworkUrl: String,
        positionMs: Long,
        durationMs: Long,
        isPlaying: Boolean,
    ) {
        if (artworkCache.get(artworkUrl) != null || !pendingArtwork.add(artworkUrl)) return
        artworkExecutor.execute {
            var connection: HttpURLConnection? = null
            try {
                connection = (URL(artworkUrl).openConnection() as HttpURLConnection).apply {
                    connectTimeout = 5000
                    readTimeout = 7000
                    instanceFollowRedirects = true
                }
                connection.inputStream.use { stream ->
                    BitmapFactory.decodeStream(stream)?.let { bitmap ->
                        artworkCache.put(artworkUrl, bitmap)
                        if (latestMediaId == mediaId) {
                            Handler(Looper.getMainLooper()).post {
                                if (latestMediaId == mediaId) {
                                    update(
                                        context = context,
                                        mediaId = mediaId,
                                        title = title,
                                        artist = artist,
                                        artwork = bitmap,
                                        positionMs = positionMs,
                                        durationMs = durationMs,
                                        isPlaying = isPlaying,
                                        artworkUrl = artworkUrl,
                                    )
                                }
                            }
                        }
                    }
                }
            } catch (_: Exception) {
                // Artwork is optional; playback and the media session continue.
            } finally {
                connection?.disconnect()
                pendingArtwork.remove(artworkUrl)
            }
        }
    }

    private fun buildMusicNotification(
        context: Context,
        mediaId: String,
        title: String,
        artist: String,
        artwork: Bitmap?,
        positionMs: Long,
        durationMs: Long,
        isPlaying: Boolean,
    ): Notification {
        val icon = if (artwork != null) {
            Icon.createWithBitmap(artwork)
        } else {
            Icon.createWithResource(context, android.R.drawable.ic_media_play)
        }

        val percent = if (durationMs > 0) {
            ((positionMs.coerceAtLeast(0) * 100L) / durationMs)
                .coerceIn(0L, 100L)
                .toInt()
        } else {
            0
        }
        val progressMode = isPlaying && durationMs > 0 && percent in 1..99
        val content = if (isPlaying) artist else "Paused · $artist"

        val extras = Bundle().apply {
            putInt("notification.superx.operation", if (islandPosted) OP_UPDATE else OP_SHOW)
            // The notification is only a transport for OriginOS. Do not show a
            // duplicate ordinary notification in the notification drawer.
            putBoolean("notification.superx.showNotify", false)
            putInt("notification.superx.template", if (progressMode) 2 else 1)
            putString("notification.superx.scene", SCENE)
            putInt("notification.superx.changedRecord", 0)
            putParcelable("notification.superx.clickResp", PendingIntent.getActivity(
                context,
                NOTIFICATION_ID,
                Intent(context, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                },
                PendingIntent.FLAG_UPDATE_CURRENT or if (Build.VERSION.SDK_INT >= 23) PendingIntent.FLAG_IMMUTABLE else 0,
            ))

            putBundle("notification.superx.baseInfos", Bundle().apply {
                putCharSequence("notification.superx.baseInfos.title", title)
                putCharSequence("notification.superx.baseInfos.content", content)
                putParcelable("notification.superx.baseInfos.icon", icon)
            })

            putBundle("notification.superx.capsule", Bundle().apply {
                putInt("notification.superx.capsule.state", 1)
                putCharSequence("notification.superx.capsule.content", title)
                putParcelable("notification.superx.capsule.icon", icon)
            })

            putBundle("notification.superx.infos", Bundle().apply {
                if (progressMode) {
                    putInt("notification.superx.infos.progress", percent)
                    putInt("notification.superx.infos.progressColor", ACCENT_COLOR)
                    putParcelableArrayList(
                        "notification.superx.infos.nodeIcon",
                        arrayListOf(icon, icon),
                    )
                    putParcelable("notification.superx.infos.indicatorIcon", icon)
                    putInt("notification.superx.infos.indicatorLoc", 1)
                } else {
                    putString("notification.superx.infos.describe", title)
                    putString("notification.superx.infos.coreInfo", content)
                    putParcelable("notification.superx.infos.image", icon)
                }
            })

            putBundle("notification.superx.shortInfos", Bundle().apply {
                putString("notification.superx.shortInfos.describeShort", title)
                putString("notification.superx.shortInfos.coreInfoShort", content)
                putParcelable("notification.superx.shortInfos.image", icon)
            })

            putBundle("notification.superx.island", Bundle().apply {
                putInt("island.superx.leftTemplate", 1)
                putInt("island.superx.rightTemplate", if (progressMode) 2 else 4)

                putBundle("island.superx.leftInfo", Bundle().apply {
                    putString("island.superx.leftInfo.content", title)
                    putParcelable("island.superx.leftInfo.icon", icon)
                })

                putBundle("island.superx.rightInfo", Bundle().apply {
                    if (progressMode) {
                        putInt("island.superx.rightInfo.progressValue", percent)
                        putInt("island.superx.rightInfo.progressState", 0)
                        putInt("island.superx.rightInfo.progressColor", ACCENT_COLOR)
                    } else {
                        putString("island.superx.rightInfo.content", content)
                        putParcelable("island.superx.rightInfo.icon", icon)
                    }
                })
            })
        }

        return Notification.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentTitle(title)
            .setContentText(content)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setExtras(extras)
            .build()
    }

    private fun isVivoDevice(): Boolean {
        val brand = Build.BRAND.orEmpty()
        val manufacturer = Build.MANUFACTURER.orEmpty()
        val isVivo = brand.contains("vivo", ignoreCase = true) ||
            brand.contains("iqoo", ignoreCase = true) ||
            manufacturer.contains("vivo", ignoreCase = true)
        return isVivo
    }

    private fun isOriginIslandAvailable(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O || !isOriginOsDevice()) return false
        val manager = context.getSystemService(NotificationManager::class.java) ?: return false
        if (Build.VERSION.SDK_INT >= 33 && !manager.areNotificationsEnabled()) {
            return false
        }
        return true
    }

    /**
     * Funtouch OS also runs on Vivo hardware but does not expose Origin Island.
     * Posting the carrier notification there only creates a silent duplicate.
     * System properties are vendor-private, so read them defensively.
     */
    private fun isOriginOsDevice(): Boolean {
        val properties = listOf("ro.vivo.os.version", "ro.vivo.os.build.display.id", "ro.vivo.os.name")
        val values = properties.mapNotNull { key ->
            runCatching {
                val systemProperties = Class.forName("android.os.SystemProperties")
                systemProperties.getMethod("get", String::class.java).invoke(null, key) as? String
            }.getOrNull()
        }
        return values.any { it.contains("originos", ignoreCase = true) }
    }

    private fun ensureChannel(manager: NotificationManager) {
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                "Loopin Origin Island",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "Playback information for Vivo/iQOO Origin Island."
                setShowBadge(false)
                setSound(null, null)
                enableVibration(false)
            },
        )
    }

    private fun registerScene(manager: NotificationManager, context: Context) {
        runCatching {
            val method = NotificationManager::class.java.getMethod(
                "setSuperXInfosSceneList",
                MutableList::class.java,
                MutableList::class.java,
                MutableList::class.java,
                MutableList::class.java,
            )
            method.invoke(
                manager,
                arrayListOf(SCENE),
                arrayListOf("true"),
                arrayListOf(context.packageName),
                arrayListOf("true"),
            )
        }
    }
}
