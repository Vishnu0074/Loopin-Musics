import 'package:flutter/services.dart';
import '../models/audio_settings.dart';

class AudioEffectsService {
  static const _channel = MethodChannel('com.example.loopin/audio_effects');
  Future<void> apply({required int sessionId, required AudioSettings settings}) async {
    try {
      await _channel.invokeMethod('apply', {
        'sessionId': sessionId, 'balance': settings.balance, 'mono': settings.mono,
        'equalizerEnabled': settings.equalizerEnabled, 'bands': settings.equalizerBands,
      });
    } catch (_) {}
  }
}
