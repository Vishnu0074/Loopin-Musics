package com.example.loopin

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.view.KeyEvent
import android.widget.RemoteViews

object LoopinWidgetManager {
    private const val PREFS_NAME = "loopin_widget_prefs"

    private const val KEY_NP_TITLE = "np_title"
    private const val KEY_NP_ARTIST = "np_artist"
    private const val KEY_NP_IS_PLAYING = "np_is_playing"

    private const val KEY_STAT_HOURS = "stat_hours"
    private const val KEY_STAT_MINS = "stat_mins"
    private const val KEY_STAT_STREAK = "stat_streak"
    private const val KEY_STAT_TOP_TRACK = "stat_top_track"
    private const val KEY_STAT_TOP_PLAYS = "stat_top_plays"

    private const val KEY_LYRICS_SONG = "lyrics_song"
    private const val KEY_LYRICS_TEXT = "lyrics_text"

    fun updateNowPlaying(
        context: Context,
        title: String,
        artist: String,
        isPlaying: Boolean
    ) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit()
            .putString(KEY_NP_TITLE, title)
            .putString(KEY_NP_ARTIST, artist)
            .putBoolean(KEY_NP_IS_PLAYING, isPlaying)
            .apply()

        val appWidgetManager = AppWidgetManager.getInstance(context)
        val componentName = ComponentName(context, NowPlayingWidgetProvider::class.java)
        val appWidgetIds = appWidgetManager.getAppWidgetIds(componentName)
        for (id in appWidgetIds) {
            updateNowPlayingWidget(context, appWidgetManager, id)
        }
    }

    fun updateNowPlayingWidget(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int
    ) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val title = prefs.getString(KEY_NP_TITLE, "Nothing Playing") ?: "Nothing Playing"
        val artist = prefs.getString(KEY_NP_ARTIST, "Tap to open Loopin") ?: "Tap to open Loopin"
        val isPlaying = prefs.getBoolean(KEY_NP_IS_PLAYING, false)

        val views = RemoteViews(context.packageName, R.layout.widget_now_playing)
        views.setTextViewText(R.id.widget_np_title, title)
        views.setTextViewText(R.id.widget_np_artist, artist)
        views.setImageViewResource(
            R.id.widget_np_play,
            if (isPlaying) R.drawable.ic_widget_pause else R.drawable.ic_widget_play
        )

        // Open app when clicking body
        val openIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val openPendingIntent = PendingIntent.getActivity(
            context,
            0,
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        views.setOnClickPendingIntent(R.id.widget_np_root, openPendingIntent)

        // Media controls
        views.setOnClickPendingIntent(
            R.id.widget_np_prev,
            createMediaPendingIntent(context, KeyEvent.KEYCODE_MEDIA_PREVIOUS, 101)
        )
        views.setOnClickPendingIntent(
            R.id.widget_np_play,
            createMediaPendingIntent(context, KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE, 102)
        )
        views.setOnClickPendingIntent(
            R.id.widget_np_next,
            createMediaPendingIntent(context, KeyEvent.KEYCODE_MEDIA_NEXT, 103)
        )

        appWidgetManager.updateAppWidget(appWidgetId, views)
    }

    fun updateStats(
        context: Context,
        totalHours: Int,
        dailyMins: Int,
        streakDays: Int,
        topTrack: String,
        topPlays: String
    ) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit()
            .putInt(KEY_STAT_HOURS, totalHours)
            .putInt(KEY_STAT_MINS, dailyMins)
            .putInt(KEY_STAT_STREAK, streakDays)
            .putString(KEY_STAT_TOP_TRACK, topTrack)
            .putString(KEY_STAT_TOP_PLAYS, topPlays)
            .apply()

        val appWidgetManager = AppWidgetManager.getInstance(context)
        val componentName = ComponentName(context, StatsWidgetProvider::class.java)
        val appWidgetIds = appWidgetManager.getAppWidgetIds(componentName)
        for (id in appWidgetIds) {
            updateStatsWidget(context, appWidgetManager, id)
        }
    }

    fun updateStatsWidget(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int
    ) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val hours = prefs.getInt(KEY_STAT_HOURS, 0)
        val mins = prefs.getInt(KEY_STAT_MINS, 0)
        val streak = prefs.getInt(KEY_STAT_STREAK, 0)
        val topTrack = prefs.getString(KEY_STAT_TOP_TRACK, "Keep listening on Loopin") ?: "Keep listening on Loopin"
        val topPlays = prefs.getString(KEY_STAT_TOP_PLAYS, "★") ?: "★"

        val views = RemoteViews(context.packageName, R.layout.widget_stats)
        views.setTextViewText(R.id.widget_stat_played, "$hours h")
        views.setTextViewText(R.id.widget_stat_today, "$mins min")
        views.setTextViewText(R.id.widget_stat_streak, "$streak d")
        views.setTextViewText(R.id.widget_stat_top_track, topTrack)
        views.setTextViewText(R.id.widget_stat_top_plays, topPlays)

        val openIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val openPendingIntent = PendingIntent.getActivity(
            context,
            201,
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        views.setOnClickPendingIntent(R.id.widget_stats_root, openPendingIntent)

        appWidgetManager.updateAppWidget(appWidgetId, views)
    }

    fun updateLyrics(
        context: Context,
        songInfo: String,
        lyricText: String
    ) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit()
            .putString(KEY_LYRICS_SONG, songInfo)
            .putString(KEY_LYRICS_TEXT, lyricText)
            .apply()

        val appWidgetManager = AppWidgetManager.getInstance(context)
        val componentName = ComponentName(context, LyricsWidgetProvider::class.java)
        val appWidgetIds = appWidgetManager.getAppWidgetIds(componentName)
        for (id in appWidgetIds) {
            updateLyricsWidget(context, appWidgetManager, id)
        }
    }

    fun updateLyricsWidget(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int
    ) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val song = prefs.getString(KEY_LYRICS_SONG, "No Song Playing") ?: "No Song Playing"
        val text = prefs.getString(KEY_LYRICS_TEXT, "Play a song with lyrics to see live verses right on your home screen.")
            ?: "Play a song with lyrics to see live verses right on your home screen."

        val views = RemoteViews(context.packageName, R.layout.widget_lyrics)
        views.setTextViewText(R.id.widget_lyrics_song, song)
        views.setTextViewText(R.id.widget_lyrics_text, text)

        val openIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val openPendingIntent = PendingIntent.getActivity(
            context,
            301,
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        views.setOnClickPendingIntent(R.id.widget_lyrics_root, openPendingIntent)

        appWidgetManager.updateAppWidget(appWidgetId, views)
    }

    private fun createMediaPendingIntent(context: Context, keyCode: Int, requestCode: Int): PendingIntent {
        val intent = Intent(Intent.ACTION_MEDIA_BUTTON).apply {
            setComponent(ComponentName(context, "com.ryanheise.audioservice.MediaButtonReceiver"))
            putExtra(Intent.EXTRA_KEY_EVENT, KeyEvent(KeyEvent.ACTION_DOWN, keyCode))
        }
        return PendingIntent.getBroadcast(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }
}
