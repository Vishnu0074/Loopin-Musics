import 'package:flutter/services.dart';

class HomeWidgetService {
  static const _channel = MethodChannel('com.example.loopin/home_widgets');

  static Future<void> updateNowPlaying({
    required String title,
    required String artist,
    required bool isPlaying,
  }) async {
    try {
      await _channel.invokeMethod('updateNowPlaying', {
        'title': title,
        'artist': artist,
        'isPlaying': isPlaying,
      });
    } catch (_) {}
  }

  static Future<void> updateStats({
    required int totalPlayedHours,
    required int dailyMinutes,
    required int listeningStreakDays,
    String? topTrack,
    String? topPlays,
  }) async {
    try {
      await _channel.invokeMethod('updateStats', {
        'totalPlayedHours': totalPlayedHours,
        'dailyMinutes': dailyMinutes,
        'listeningStreakDays': listeningStreakDays,
        'topTrack': topTrack ?? 'Keep listening on Loopin',
        'topPlays': topPlays ?? '★',
      });
    } catch (_) {}
  }

  static Future<void> updateLyrics({
    required String song,
    required String text,
  }) async {
    try {
      await _channel.invokeMethod('updateLyrics', {
        'song': song,
        'text': text,
      });
    } catch (_) {}
  }
}
