import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:web/web.dart' as web;

/// Publishes Loopin's active track to the browser Media Session API.
///
/// macOS reads this metadata from the browser tab and uses it in the system
/// Now Playing controls. This implementation is isolated to Flutter Web.
class MediaSessionService {
  static bool _handlersRegistered = false;
  static Future<void> Function()? _onPlay;
  static Future<void> Function()? _onPause;
  static Future<void> Function()? _onNext;
  static Future<void> Function()? _onPrevious;
  static Future<void> Function(Duration position)? _onSeek;
  static DateTime? _lastPositionUpdate;

  static void update({
    required String title,
    required String artist,
    required String album,
    required String artworkUrl,
    required bool playing,
    required Duration position,
    Duration? duration,
    required Future<void> Function() onPlay,
    required Future<void> Function() onPause,
    required Future<void> Function() onNext,
    required Future<void> Function() onPrevious,
    required Future<void> Function(Duration position) onSeek,
  }) {
    try {
      final session = web.window.navigator.mediaSession;

      _onPlay = onPlay;
      _onPause = onPause;
      _onNext = onNext;
      _onPrevious = onPrevious;
      _onSeek = onSeek;
      _registerHandlers(session);

      final artworkList = <web.MediaImage>[];
      if (artworkUrl.trim().isNotEmpty) {
        artworkList.add(
          web.MediaImage(
            src: artworkUrl,
            sizes: '512x512',
          ),
        );
      }

      session.metadata = web.MediaMetadata(
        web.MediaMetadataInit(
          title: title,
          artist: artist,
          album: album,
          artwork: artworkList.toJS,
        ),
      );

      session.playbackState = playing ? 'playing' : 'paused';

      // Position updates are throttled because browsers do not need a new
      // position state for every audio position event.
      final now = DateTime.now();
      if (_lastPositionUpdate == null ||
          now.difference(_lastPositionUpdate!) >= const Duration(seconds: 1)) {
        final total = duration?.inMilliseconds ?? 0;
        if (total > 0) {
          session.setPositionState(
            web.MediaPositionState(
              duration: total / 1000,
              playbackRate: 1,
              position: (position.inMilliseconds / 1000).clamp(0, total / 1000),
            ),
          );
          _lastPositionUpdate = now;
        }
      }
    } catch (_) {
      // Media Session is an enhancement; unsupported browsers must still play.
    }
  }

  static void clear() {
    try {
      final session = web.window.navigator.mediaSession;
      session.metadata = null;
      session.playbackState = 'none';
    } catch (_) {
      // Ignore unsupported or partially implemented Media Session APIs.
    }
  }

  static void _registerHandlers(web.MediaSession session) {
    if (_handlersRegistered) return;
    _handlersRegistered = true;

    void register(String action, Future<void> Function()? Function() callback) {
      try {
        session.setActionHandler(
          action,
          ((JSObject? details) {
            final actionCallback = callback();
            if (actionCallback != null) {
              unawaited(actionCallback().catchError((Object _) {}));
            } else if (action == 'seekto' && details != null && _onSeek != null) {
              if (details.hasProperty('seekTime'.toJS).toDart) {
                final seekTime = details.getProperty<JSNumber?>('seekTime'.toJS);
                if (seekTime != null) {
                  final seconds = seekTime.toDartDouble;
                  unawaited(_onSeek!(Duration(milliseconds: (seconds * 1000).round()))
                      .catchError((Object _) {}));
                }
              }
            }
          }).toJS,
        );
      } catch (_) {
        // Some browsers implement only a subset of media actions.
      }
    }

    register('play', () => _onPlay);
    register('pause', () => _onPause);
    register('nexttrack', () => _onNext);
    register('previoustrack', () => _onPrevious);
    register('seekto', () => null);
  }
}
