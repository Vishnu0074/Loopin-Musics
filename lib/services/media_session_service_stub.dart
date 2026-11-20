/// No-op implementation used on non-web platforms.
class MediaSessionService {
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
  }) {}

  static void clear() {}
}
