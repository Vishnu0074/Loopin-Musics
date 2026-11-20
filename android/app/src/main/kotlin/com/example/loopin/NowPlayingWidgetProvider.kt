package com.example.loopin

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context

class NowPlayingWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            LoopinWidgetManager.updateNowPlayingWidget(context, appWidgetManager, appWidgetId)
        }
    }
}
