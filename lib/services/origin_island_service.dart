import 'package:flutter/services.dart';

class OriginIslandService {
  static const _channel = MethodChannel('com.example.loopin/origin_island');

  static Future<void> requestNotificationPermission() async {
    try {
      await _channel.invokeMethod<void>('requestNotificationPermission');
    } on MissingPluginException {
      // iOS and non-Android targets do not need this permission.
    } on PlatformException {
      // Best-effort permission request.
    }
  }

  static Future<void> update({
    String? mediaId,
    required String title,
    required String artist,
    required Duration position,
    required Duration? duration,
    required bool isPlaying,
    String? artworkUrl,
  }) async {
    try {
      await _channel.invokeMethod<void>('update', {
        'mediaId': mediaId ?? '',
        'title': title,
        'artist': artist,
        'positionMs': position.inMilliseconds,
        'durationMs': duration?.inMilliseconds ?? 0,
        'isPlaying': isPlaying,
        'artworkUrl': artworkUrl ?? '',
      });
    } on MissingPluginException {
      // iOS and non-Android targets simply do not have Origin Island.
    } on PlatformException {
      // OriginOS support is best-effort and must never interrupt playback.
    }
  }

  static Future<void> clear() async {
    try {
      await _channel.invokeMethod<void>('clear');
    } on MissingPluginException {
      // Best-effort cleanup.
    } on PlatformException {
      // Best-effort cleanup.
    }
  }
}
