import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Lists meaningful Android output choices and requests a preferred device
/// for Loopin's own just_audio/ExoPlayer playback track.
class AudioOutputService {
  static const MethodChannel _channel =
      MethodChannel('com.example.loopin/audio_output');
  static const MethodChannel _playerChannel =
      MethodChannel('com.ryanheise.just_audio.methods');

  Future<List<Map<String, dynamic>>> availableOutputs() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return const [];
    }
    try {
      final result =
          await _channel.invokeListMethod<Map<dynamic, dynamic>>(
        'getAvailableOutputs',
      );
      return (result ?? const [])
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false);
    } on PlatformException {
      return const [];
    }
  }

  Future<bool> selectOutput(int? deviceId) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }
    try {
      final playerCount = await _playerChannel.invokeMethod<int>(
        'setPreferredAudioDevice',
        <String, dynamic>{'deviceId': deviceId},
      );
      return (playerCount ?? 0) > 0;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  bool get isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
}
