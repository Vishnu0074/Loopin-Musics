import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import '../models/song.dart';
import 'home_widget_service.dart';
import 'lyrics_service.dart';
import 'monochrome_api.dart';
import 'origin_island_service.dart';
import 'debug_log_service.dart';
import 'recommendation_service.dart';
import '../models/audio_settings.dart';
import 'audio_settings_service.dart';
import 'audio_effects_service.dart';
import 'service_config_service.dart';
import 'track_normalizer.dart';
import 'stats_service.dart';
import 'realtime_player_service.dart';
import 'media_session_service_stub.dart'
    if (dart.library.js_interop) 'media_session_service_web.dart';

final _audioLog = LoopinDebugLogService.instance;

class GlobalAudioService with WidgetsBindingObserver {
  static final GlobalAudioService _instance = GlobalAudioService._internal();
  late final Future<void> ready;
  AudioPlayer? _player;
  ConcatenatingAudioSource? _playlist;
  final _queueController = StreamController<List<Song>>.broadcast();
  final _currentIndexController = StreamController<int?>.broadcast();
  final _recommendations = RecommendationService();
  final _monochrome = MonochromeApi();
  final _lyricsService = LyricsService();
  LyricsData? _currentLyricsData;
  String? _currentLyricsSongId;
  int? _lastWidgetLyricIndex;
  Future<void>? _recommendationJob;
  int? _recommendationJobGeneration;
  int _queueGeneration = 0;
  Future<void>? _completionAdvanceJob;
  int _recommendationFailures = 0;
  List<Song> _pendingRecommendationCandidates = [];
  DateTime? _nextRecommendationRetryAt;
  StreamSubscription<int?>? _indexSubscription;
  StreamSubscription<PlayerState>? _playerStateSubscription;
  StreamSubscription<PlaybackEvent>? _playbackEventSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  DateTime? _lastOriginIslandUpdate;
  bool _originPermissionRequested = false;
  AudioSettings _audioSettings = const AudioSettings();
  StreamSubscription<int?>? _audioSessionSubscription;
  List<Song> _queue = const [];
  int? _currentIndex;
  final _realtime = RealtimePlayerService();
  bool _applyingRemoteState = false;
  bool _applyingRemoteCommand = false;
  DateTime? _lastRemoteSync;
  int _lastRealtimeRevision = 0;
  Map<String, dynamic>? _pendingRealtimeState;
  final List<Map<String, dynamic>> _pendingRealtimePlaybackEvents = [];
  Future<void>? _realtimeSyncJob;
  bool _realtimeSyncPending = false;
  bool _realtimeSyncForcePending = false;
  bool? _lastObservedPlaying;
  Timer? _backgroundSyncTimer;

  // Maintain a substantial rolling queue without resolving every stream URL
  // up front. The local recommendation engine ranks candidates; the player
  // resolves only the next small group.
  static const int _recommendationRefillThreshold = 12;
  static const int _recommendationTargetAhead = 50;
  static const int _recommendationResolvePerRequest = 12;

  // just_audio exposes volume control, so we can make both manual and automatic
  // track transitions feel intentional without replacing the existing player.
  bool _manualTransitionInProgress = false;
  bool _replacingQueue = false;
  int _playSelectionGeneration = 0;
  Future<void> _queueMutationJob = Future<void>.value();
  Future<void> _remoteCommandJob = Future<void>.value();
  Future<void>? _seekJob;
  Duration? _pendingSeekPosition;

  factory GlobalAudioService() => _instance;
  GlobalAudioService._internal() {
    WidgetsBinding.instance.addObserver(this);
    _backgroundSyncTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      // The timer keeps the realtime state reconciled while Android leaves the
      // audio foreground service alive. If the Flutter isolate is suspended,
      // resume() below performs the authoritative catch-up when it returns.
      if (_player?.playing == true) unawaited(_syncRealtime(force: true));
    });
    ready = _initialize();
    unawaited(_realtime.connect(
      onCommand: _handleRealtimeCommand,
      onState: _handleRealtimeState,
      onLyrics: _handleRealtimeLyrics,
      onQueue: _handleRealtimeQueue,
      onPlaybackEvent: _handleRealtimePlaybackEvent,
      onCommandResult: _handleRealtimeCommandResult,
      onOwnershipChanged: (isOwner) {
        if (isOwner) unawaited(_syncRealtime(force: true));
      },
      onConnected: () {
        // Start a fresh local revision window when a realtime session connects.
        _lastRealtimeRevision = 0;
        _pendingRealtimeState = null;
        _pendingRealtimePlaybackEvents.clear();
      },
    ));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Android can suspend the Dart isolate while the media foreground service
      // keeps playback alive. Never close the socket on pause/background;
      // instead reconnect and reconcile immediately when Flutter resumes.
      unawaited(_realtime.resume());
      unawaited(_syncRealtime(force: true));
    }
  }

  Future<void> _initialize() async {
    // Background notifications are provided by the mobile plugin. Windows
    // uses the desktop just_audio implementation without initializing it.
    if (!kIsWeb && defaultTargetPlatform != TargetPlatform.windows) {
      await JustAudioBackground.init(
        androidNotificationChannelId: 'com.example.loopin.audio',
        androidNotificationChannelName: 'Loopin Playback',
        androidNotificationOngoing: true,
      );
    }
    _player = AudioPlayer();
    _audioSettings = await AudioSettingsService().load();
    if (defaultTargetPlatform == TargetPlatform.android) {
      _audioSessionSubscription = _player!.androidAudioSessionIdStream.listen((id) {
        if (id != null) unawaited(_applyNativeEffects(id));
      });
    }
    _indexSubscription = _player!.currentIndexStream.listen((index) {
      _currentIndex = index;
      if (_replacingQueue) return;
      _currentIndexController.add(index);

      final song = index != null && index >= 0 && index < _queue.length ? _queue[index] : null;
      if (song != null) {
        _syncWebMediaSession(song: song);
        // Only the authoritative device owns recommendation generation and
        // listening statistics. Followers mirror its queue instead of creating
        // a competing recommendation list of their own.
        if (_realtime.isPlaybackOwner) {
          _recommendations.recordPlay(song);
          unawaited(StatsService().recordSongPlayed(song));
          unawaited(_refreshRecommendationsForCurrentTrack());
        }
        unawaited(_fetchLyricsForWidget(song));
      }
      // Track transitions must bypass the normal realtime throttle.
      unawaited(_syncRealtime(force: true));
      unawaited(_syncOriginIsland(force: true));
    });
    _playbackEventSubscription = _player!.playbackEventStream.listen((_) {}, onError: (Object error, StackTrace stack) {
      _audioLog.error('AUDIO playback error: $error');
      _audioLog.error(stack.toString().replaceAll(RegExp(r'\\s+'), ' ').trim());
    });
    _playerStateSubscription = _player!.playerStateStream.listen((state) {
      if (_replacingQueue) {
        _lastObservedPlaying = state.playing;
        return;
      }
      _syncWebMediaSession();
      if (_realtime.isPlaybackOwner && _lastObservedPlaying != state.playing) {
        _lastObservedPlaying = state.playing;
        final index = _currentIndex;
        final trackId = index != null && index >= 0 && index < _queue.length ? _queue[index].id : null;
        unawaited(_realtime.publishPlaybackEvent(state.playing ? 'play' : 'pause', trackId: trackId));
      }
      if (state.processingState == ProcessingState.completed) {
        unawaited(_handlePlaybackCompleted());
        unawaited(OriginIslandService.clear());
      } else {
        unawaited(_syncOriginIsland(force: true));
      }
    });
    _positionSubscription = _player!.positionStream.listen((pos) {
      if (_replacingQueue) return;
      _syncWebMediaSession();
      // Position ticks are local UI/lyrics updates. Explicit events and periodic
      // snapshots keep remote clients synchronized without flooding the socket.
      unawaited(_syncOriginIsland());
      _updateWidgetLyricsLine();
      final index = _currentIndex;
      if (_realtime.isPlaybackOwner &&
          index != null && index >= 0 && index < _queue.length) {
        unawaited(StatsService().recordActiveProgress(pos, _queue[index]));
      }

      // Refill before the listener can hear the end of the queue. This also
      // retries recommendation generation if a previous network/stream
      // resolution attempt failed, instead of waiting until playback stops.
      if (_realtime.isPlaybackOwner &&
          _remainingAhead < _recommendationRefillThreshold) {
        unawaited(_ensureRecommendations());
      }

      // Keep output volume constant during automatic transitions.
    });
    // If the WebSocket ownership handshake completed before the player was
    // initialized, publish the now-ready local state once initialization ends.
    unawaited(_syncRealtime(force: true));
  }

  void _syncWebMediaSession({Song? song}) {
    if (!kIsWeb) return;
    final activePlayer = _player;
    if (activePlayer == null) return;

    final index = activePlayer.currentIndex ?? _currentIndex;
    final activeSong = song ??
        (index != null && index >= 0 && index < _queue.length
            ? _queue[index]
            : null);
    if (activeSong == null) {
      MediaSessionService.clear();
      return;
    }

    MediaSessionService.update(
      title: TrackNormalizer.unescapeHtml(activeSong.title),
      artist: TrackNormalizer.unescapeHtml(activeSong.artist),
      album: activeSong.album == null
          ? 'Loopin'
          : TrackNormalizer.unescapeHtml(activeSong.album!),
      artworkUrl: activeSong.imageUrl,
      playing: activePlayer.playing,
      position: activePlayer.position,
      duration: activePlayer.duration,
      onPlay: () async {
        if (!_realtime.isPlaybackOwner) {
          await _realtime.sendCommand('play');
          return;
        }
        final currentPlayer = await player;
        unawaited(currentPlayer.play());
      },
      onPause: () async {
        if (!_realtime.isPlaybackOwner) {
          await _realtime.sendCommand('pause');
          return;
        }
        final currentPlayer = await player;
        await currentPlayer.pause();
      },
      onNext: next,
      onPrevious: previous,
      onSeek: seek,
    );
  }

  Future<AudioPlayer> get player async { await ready; return _player!; }
  Stream<List<Song>> get queueStream => _queueController.stream;
  Stream<int?> get currentIndexStream => _currentIndexController.stream;
  Stream<Duration> get positionStream => _player?.positionStream ?? const Stream.empty();
  Stream<PlayerState> get playerStateStream => _player?.playerStateStream ?? const Stream.empty();
  Duration get currentPosition => _player?.position ?? Duration.zero;
  List<Song> get queue => List.unmodifiable(_queue);
  int? get currentIndex => _currentIndex;

  Future<void> seek(Duration position) async {
    if (!_realtime.isPlaybackOwner) {
      await _realtime.sendCommand('seek', positionMs: position.inMilliseconds);
      return;
    }
    final p = await player;
    final duration = p.duration;
    var target = position.isNegative ? Duration.zero : position;
    if (duration != null && target > duration) target = duration;
    _pendingSeekPosition = target;
    final activeJob = _seekJob;
    if (activeJob != null) {
      await activeJob;
      return;
    }
    final job = _drainSeekRequests(p);
    _seekJob = job;
    try {
      await job;
    } finally {
      if (identical(_seekJob, job)) _seekJob = null;
      if (_pendingSeekPosition != null) {
        unawaited(seek(_pendingSeekPosition!));
      }
    }
    final activeIndex = _currentIndex;
    final activeSong = activeIndex != null && activeIndex >= 0 && activeIndex < _queue.length ? _queue[activeIndex] : null;
    unawaited(_realtime.publishPlaybackEvent('seek', positionMs: p.position.inMilliseconds, trackId: activeSong?.id));
    unawaited(_syncRealtime(force: true));
  }

  Future<void> _drainSeekRequests(AudioPlayer player) async {
    while (_pendingSeekPosition != null) {
      final target = _pendingSeekPosition!;
      _pendingSeekPosition = null;
      try {
        await player.seek(target);
      } catch (error) {
        _audioLog.warning('AUDIO seek failed: $error');
      }
    }
  }

  Future<void> playAtIndex(int index) async {
    _playSelectionGeneration++;
    if (!_realtime.isPlaybackOwner) {
      if (index >= 0 && index < _queue.length) {
        final song = _queue[index];
        await _realtime.sendPlayTrack({'id': song.id, 'title': song.title, 'artist': song.artist, 'album': song.album, 'image_url': song.imageUrl, 'language': song.language, 'genre': song.genre, 'tempo': song.tempo, 'duration_seconds': song.durationSeconds});
      }
      return;
    }
    final p = await player;
    if (_manualTransitionInProgress || index < 0 || index >= _queue.length ||
        index >= (p.sequence?.length ?? 0)) {
      return;
    }
    if (index == (p.currentIndex ?? _currentIndex)) {
      if (!p.playing) {
        unawaited(p.play().catchError((Object error, StackTrace stack) {
          _audioLog.error('AUDIO resume failed: $error');
        }));
      }
      return;
    }
    await _transitionToIndex(p, index);
    await _syncRealtime(force: true);
  }

  Future<void> setQueue(List<Song> songs, {int initialIndex = 0, int? selectionGeneration}) async {
    if (songs.isEmpty) return;
    final activePlayer = await player;
    final previousMutation = _queueMutationJob;
    final mutationDone = Completer<void>();
    _queueMutationJob = mutationDone.future;
    try {
      await previousMutation;
      // A newer Home/Search selection may have arrived while this request was
      // waiting for a previous source mutation. Never let an older tap win.
      if (selectionGeneration != null &&
          selectionGeneration != _playSelectionGeneration) {
        return;
      }
      _queueGeneration++;
      // A new explicit queue selection invalidates any unprocessed candidates
      // generated for the previous seed track.
      _pendingRecommendationCandidates = [];
      _manualTransitionInProgress = false;

      final sources = songs.map((song) => AudioSource.uri(
        Uri.parse(song.mediaUrl),
        tag: MediaItem(
          id: song.id,
          album: song.album ?? 'Loopin',
          title: song.title,
          artist: song.artist,
          artUri: Uri.tryParse(song.imageUrl),
        ),
      )).toList();
      final safeIndex = initialIndex.clamp(0, sources.length - 1);
      final nextPlaylist = ConcatenatingAudioSource(children: sources);

      // Keep the old queue metadata intact until just_audio confirms that the
      // replacement source has loaded successfully.
      _replacingQueue = true;
      try {
        // Attach the source without waiting for full media preloading. The
        // subsequent play() call starts loading and buffering immediately.
        await activePlayer.setAudioSource(
          nextPlaylist,
          initialIndex: safeIndex,
          initialPosition: Duration.zero,
          preload: false,
        ).timeout(const Duration(seconds: 15));
        _queue = List.of(songs);
        _playlist = nextPlaylist;
        _currentIndex = safeIndex;
      } catch (_) {
        _currentIndex = activePlayer.currentIndex;
        _currentIndexController.add(_currentIndex);
        rethrow;
      } finally {
        _replacingQueue = false;
      }

      _queueController.add(List.unmodifiable(_queue));
      _currentIndexController.add(_currentIndex);
      final selectedSong = _queue[safeIndex];
      _syncWebMediaSession(song: selectedSong);
      if (_realtime.isPlaybackOwner) {
        _recommendations.recordPlay(selectedSong);
        unawaited(StatsService().recordSongPlayed(selectedSong));
      }
      unawaited(_fetchLyricsForWidget(selectedSong));
    } finally {
      _replacingQueue = false;
      mutationDone.complete();
    }
    unawaited(_syncOriginIsland(force: true));
    // Queue replacement is a track-selection event; publish the new track
    // and ordered queue immediately instead of waiting for the 20s snapshot.
    unawaited(_syncRealtime(force: true));
  }
  Future<void> playSong(Song song, {List<Song>? context}) async {
    if (!_realtime.isPlaybackOwner) {
      await _realtime.sendPlayTrack({'id': song.id, 'title': song.title, 'artist': song.artist, 'album': song.album, 'image_url': song.imageUrl, 'language': song.language, 'genre': song.genre, 'duration_seconds': song.durationSeconds});
      return;
    }
    // Explicit selections must resolve a fresh stream instead of reusing a
    // possibly stale queue entry with an expired media URL.
    final selectionGeneration = ++_playSelectionGeneration;
    final services = ServiceConfigService();
    // Never put a network round-trip on the tap-to-play path. Use the last
    // known service configuration (fail open before the first response) and
    // refresh it in the background for the next selection.
    final streamingEnabled = services.enabledCached('streaming');
    final highQualityEnabled = services.enabledCached('high_quality_audio');
    unawaited(services.refresh());
    if (!streamingEnabled) {
      throw StateError('Music streaming is temporarily unavailable.');
    }
    if (!highQualityEnabled && _audioSettings.quality == '320') {
      _audioSettings = _audioSettings.copyWith(quality: 'auto');
    }
    final quality = highQualityEnabled ? _audioSettings.quality : 'auto';
    final directMediaUrl = await _monochrome.resolveStream(song, quality: quality);
    if (!_realtime.isPlaybackOwner || selectionGeneration != _playSelectionGeneration) return;
    if (directMediaUrl == null) {
      throw StateError('No playable stream was found for "${song.title}".');
    }

    // Use the provider's direct stream URL on every platform. No catalog
    // proxy or short-lived backend token is involved in playback.
    final playableSong = Song(
      id: song.id,
      title: TrackNormalizer.unescapeHtml(song.title),
      artist: TrackNormalizer.unescapeHtml(song.artist),
      album: song.album != null ? TrackNormalizer.unescapeHtml(song.album!) : null,
      imageUrl: song.imageUrl,
      mediaUrl: directMediaUrl,
      isrc: song.isrc,
      language: song.language,
      durationSeconds: song.durationSeconds,
      tempo: song.tempo,
      genre: song.genre,
      lyricsId: song.lyricsId,
    );

    final remainingContext = <Song>[];
    if (context != null && context.isNotEmpty) {
      final startIndex = context.indexWhere((s) => s.id == song.id || TrackNormalizer.isDuplicate(s, song));
      final orderedList = startIndex >= 0
          ? [...context.skip(startIndex + 1), ...context.take(startIndex)]
          : context.where((s) => s.id != song.id && !TrackNormalizer.isDuplicate(s, song)).toList();

      for (final candidate in orderedList) {
        if (!remainingContext.any((existing) => TrackNormalizer.isDuplicate(existing, candidate)) &&
            !TrackNormalizer.isDuplicate(song, candidate)) {
          remainingContext.add(candidate);
        }
      }
    }

    if (!_realtime.isPlaybackOwner || selectionGeneration != _playSelectionGeneration) return;
    try {
      await setQueue([playableSong], selectionGeneration: selectionGeneration);
    } catch (error) {
      if (!_realtime.isPlaybackOwner || selectionGeneration != _playSelectionGeneration) return;
      _audioLog.warning('Direct Monochrome audio source failed: $error');
      rethrow;
    }
    if (!_realtime.isPlaybackOwner || selectionGeneration != _playSelectionGeneration) return;
    final player = await this.player;

    // just_audio's play() future completes when playback stops or finishes,
    // not when playback has merely started. Do not await it here: awaiting it
    // would defer recommendation generation until the selected song ends.
    // Kick off playback first, then let queue generation run independently.
    unawaited(player.play().catchError((Object error, StackTrace stack) {
      _audioLog.error('AUDIO failed to start playback: $error');
      _audioLog.error(stack.toString().replaceAll(RegExp(r'\\s+'), ' ').trim());
    }));

    // Permission prompts and now-playing metadata must not delay audio start.
    if (!_originPermissionRequested) {
      _originPermissionRequested = true;
      unawaited(OriginIslandService.requestNotificationPermission());
    }
    unawaited(_syncOriginIsland(force: true));

    // Start personalized discovery alongside playback. A context/playlist
    // queue is preserved while local recommendations fill the rolling queue.
    _pendingRecommendationCandidates = remainingContext;
    unawaited(_ensureRecommendations(force: true));
  }

  Future<String?> _resolvePlaybackUrl(Song song, {required String quality}) =>
      _monochrome.resolveStream(song, quality: quality);

  Future<List<Song>> _resolveRemoteQueue(List<Song> songs) async {
    final resolved = <Song>[];
    // Resolve in small batches to avoid opening dozens of provider requests
    // when a follower joins an already-running long queue.
    for (var offset = 0; offset < songs.length; offset += 4) {
      final batch = songs.skip(offset).take(4).toList();
      final playableBatch = await Future.wait(batch.map((song) async {
        try {
          final mediaUrl = await _resolvePlaybackUrl(
            song,
            quality: _audioSettings.quality,
          );
          if (mediaUrl == null) return song;
          return Song(
            id: song.id,
            title: song.title,
            artist: song.artist,
            album: song.album,
            imageUrl: song.imageUrl,
            mediaUrl: mediaUrl,
            isrc: song.isrc,
            language: song.language,
            durationSeconds: song.durationSeconds,
            tempo: song.tempo,
            genre: song.genre,
            lyricsId: song.lyricsId,
          );
        } catch (error) {
          _audioLog.warning('Remote queue stream resolution failed for ${song.id}: $error');
          return song;
        }
      }));
      resolved.addAll(playableBatch);
    }
    return resolved;
  }

  int get _remainingAhead {
    final index = _currentIndex;
    if (index == null || index < 0 || index >= _queue.length) return 0;
    return _queue.length - index - 1;
  }

  Future<void> _ensureRecommendations({bool force = false}) {
    final activeJob = _recommendationJob;
    if (activeJob != null) {
      if (_recommendationJobGeneration == _queueGeneration && !force) return activeJob;
      return activeJob.catchError((Object _) {}).then((_) => _ensureRecommendations(force: force));
    }
    final retryAt = _nextRecommendationRetryAt;
    if (!force && retryAt != null && DateTime.now().isBefore(retryAt)) {
      return Future<void>.value();
    }
    if (force) _nextRecommendationRetryAt = null;
    _recommendationJobGeneration = _queueGeneration;
    _recommendationJob = _populateRecommendations(force: force).whenComplete(() {
      _recommendationJob = null;
      _recommendationJobGeneration = null;
    });
    return _recommendationJob!;
  }

  Future<void> _handlePlaybackCompleted() {
    if (_completionAdvanceJob != null) return _completionAdvanceJob!;
    _completionAdvanceJob = _advanceAfterCompletion().whenComplete(() {
      _completionAdvanceJob = null;
    });
    return _completionAdvanceJob!;
  }

  Future<void> _advanceAfterCompletion() async {
    if (!_realtime.isPlaybackOwner) return;
    final player = await this.player;
    final completedIndex = player.currentIndex ?? _currentIndex;
    if (completedIndex != null && completedIndex >= 0 && completedIndex < _queue.length) {
      _recommendations.recordCompletion(_queue[completedIndex]);
    }

    // just_audio normally advances while a next source is loaded. If the queue
    // ran dry, however, it enters completed; adding sources later does not
    // restart it. Force a refill attempt and explicitly resume the next source.
    if (player.loopMode == LoopMode.one || player.processingState != ProcessingState.completed) return;

    await _ensureRecommendations(force: true);
    if (player.processingState != ProcessingState.completed) return;

    final index = player.currentIndex ?? completedIndex;
    if (index == null) return;
    final nextIndex = index + 1;
    final sequenceLength = player.sequence?.length ?? 0;
    if (nextIndex >= sequenceLength || nextIndex >= _queue.length) {
      _audioLog.warning('Playback completed with no playable next track; queue refill failed or returned no playable songs.');
      return;
    }

    try {
      await player.seek(Duration.zero, index: nextIndex);
      unawaited(player.play().catchError((Object error, StackTrace stack) {
              _audioLog.error('AUDIO play failed: $error');
            }));
      _audioLog.success('Auto-advanced to next track after queue refill.');
      await _syncRealtime(force: true);
    } catch (error) {
      _audioLog.error('Auto-advance failed after track completion: $error');
    }
  }

  void _scheduleRecommendationRetry() {
    _recommendationFailures = (_recommendationFailures + 1).clamp(1, 5).toInt();
    final seconds = (5 * (1 << (_recommendationFailures - 1))).clamp(5, 80).toInt();
    _nextRecommendationRetryAt = DateTime.now().add(Duration(seconds: seconds));
  }

  Future<void> _refreshRecommendationsForCurrentTrack() async {
    if (!_realtime.isPlaybackOwner) return;
    // Track changes should preserve the upcoming queue. The refill method
    // appends unique recommendations only when the remaining queue is short.
    await _ensureRecommendations();
  }

  Future<void> _populateRecommendations({bool force = false}) async {
    if (!_realtime.isPlaybackOwner) return;
    if (_currentIndex == null || _currentIndex! < 0 || _currentIndex! >= _queue.length) return;
    if (!force && _remainingAhead >= _recommendationRefillThreshold) return;

    final playlist = _playlist;
    if (playlist == null) {
        return;
      }
    final queueGeneration = _queueGeneration;

    // This is a rolling queue, not a one-shot playlist. Whenever the listener
    // gets close to the end, ask the local recommendation engine for another batch
    // until there is a healthy amount of music ahead. If stream resolution
    // rejects some candidates, later candidates are still attempted.
    var attempts = 0;
    while (_realtime.isPlaybackOwner &&
        attempts < 6 &&
        _remainingAhead < _recommendationTargetAhead) {
      attempts++;
      final currentIndex = _currentIndex;
      if (currentIndex == null || currentIndex < 0 || currentIndex >= _queue.length) return;
      final current = _queue[currentIndex];

      List<Song> recommendations;
      try {
        // Consume the previous ranked batch before discovering more candidates.
        // This avoids repeating the same provider searches
        // for every +12 refill and keeps recommendation generation off the
        // playback-critical path.
        if (_pendingRecommendationCandidates.isNotEmpty) {
          // Consume only the next resolution-sized slice. Clearing the whole
          // buffer here discarded every candidate beyond the first 12.
          final takeCount = _pendingRecommendationCandidates.length
              .clamp(1, _recommendationResolvePerRequest);
          recommendations = _pendingRecommendationCandidates
              .take(takeCount)
              .toList();
          _pendingRecommendationCandidates = _pendingRecommendationCandidates
              .skip(takeCount)
              .toList();
        } else {
          recommendations = await _recommendations.buildRecommendations(
            current,
            limit: 50,
            currentQueue: _queue,
          );
          if (queueGeneration != _queueGeneration || !identical(_playlist, playlist)) {
        return;
      }
          if (recommendations.length > _recommendationResolvePerRequest) {
            _pendingRecommendationCandidates = recommendations
                .skip(_recommendationResolvePerRequest)
                .toList();
            recommendations = recommendations
                .take(_recommendationResolvePerRequest)
                .toList();
          }
        }
      } catch (error) {
        _scheduleRecommendationRetry();
        _audioLog.warning('Recommendation page failed; retry scheduled: $error');
        return;
      }

      if (recommendations.isEmpty) {
        _scheduleRecommendationRetry();
        _audioLog.warning('Recommendation page returned no candidates; retry scheduled.');
        return;
      }

      var added = 0;
      final neededAhead = (_recommendationTargetAhead - _remainingAhead)
          .clamp(1, _recommendationResolvePerRequest)
          .toInt();
      for (var offset = 0;
          offset < recommendations.length && added < neededAhead;
          offset += 4) {
        final batch = recommendations.skip(offset).take(4).toList();

        final resolved = await Future.wait(batch.map((candidate) async {
          try {
            final mediaUrl = await _resolvePlaybackUrl(candidate, quality: _audioSettings.quality);
            if (mediaUrl == null) return null;

            return Song(
              id: candidate.id,
              title: TrackNormalizer.unescapeHtml(candidate.title),
              artist: TrackNormalizer.unescapeHtml(candidate.artist),
              album: candidate.album != null
                  ? TrackNormalizer.unescapeHtml(candidate.album!)
                  : null,
              imageUrl: candidate.imageUrl,
              mediaUrl: mediaUrl,
              isrc: candidate.isrc,
              language: candidate.language,
              durationSeconds: candidate.durationSeconds,
              tempo: candidate.tempo,
              genre: candidate.genre,
              lyricsId: candidate.lyricsId,
            );
          } catch (error) {
            _audioLog.warning(
              'AUDIO recommendation resolve failed: $error',
            );
            return null;
          }
        }));
        if (queueGeneration != _queueGeneration || !identical(_playlist, playlist)) {
          return;
        }

        final newlyAdded = <Song>[];
        for (final playable in resolved.whereType<Song>()) {
          if (!_realtime.isPlaybackOwner || queueGeneration != _queueGeneration || !identical(_playlist, playlist)) {
          return;
        }
          // The queue can still change while requests are in flight, so avoid
          // appending a track already inserted by another result batch.
          if (_queue.any((existing) => TrackNormalizer.isDuplicate(existing, playable))) {
            continue;
          }
          await playlist.add(
            AudioSource.uri(
              Uri.parse(playable.mediaUrl),
              tag: MediaItem(
                id: playable.id,
                album: playable.album ?? 'Loopin',
                title: playable.title,
                artist: playable.artist,
                artUri: Uri.tryParse(playable.imageUrl),
              ),
            ),
          );
          if (queueGeneration != _queueGeneration || !identical(_playlist, playlist)) {
          return;
        }
          _queue = [..._queue, playable];
          newlyAdded.add(playable);
          added++;
        }

        if (newlyAdded.isNotEmpty) {
          _recommendations.recordQueueGenerated(newlyAdded);
        }
      }

      _queueController.add(List.unmodifiable(_queue));
      if (added > 0) {
        // Publish immediately so web, mobile, and desktop followers all receive
        // the exact same ordered queue without waiting for a position tick.
        unawaited(_syncRealtime(force: true));
      }
      if (added == 0) {
        // Do not spin forever on an exhausted/broken provider response.
        _scheduleRecommendationRetry();
        return;
      }
      _recommendationFailures = 0;
      _nextRecommendationRetryAt = null;
    }
  }

  Future<void> applyAudioSettings(AudioSettings settings) async {
    _audioSettings = settings;
    final id = _player?.androidAudioSessionId;
    if (id != null) await _applyNativeEffects(id);
  }

  Future<void> _applyNativeEffects(int sessionId) async {
    await AudioEffectsService().apply(sessionId: sessionId, settings: _audioSettings);
  }

  Future<void> next() async {
    _playSelectionGeneration++;
    if (!_realtime.isPlaybackOwner) {
      await _realtime.sendCommand('next');
      return;
    }
    if (_manualTransitionInProgress) return;
    final player = await this.player;
    var index = player.currentIndex ?? _currentIndex;
    if (index != null && index >= 0 && index < _queue.length) {
      _recommendations.recordSkip(_queue[index], listened: player.position);
    }

    // Refill in the background; never hold the Next button hostage to a
    // recommendation/API request when there is already a queued track.
    if (_remainingAhead < 3) {
      unawaited(_ensureRecommendations());
    }

    index = player.currentIndex ?? _currentIndex;
    var targetIndex = index == null ? 0 : index + 1;
    if (targetIndex >= 0 &&
        targetIndex < _queue.length &&
        targetIndex < (player.sequence?.length ?? 0)) {
      await _transitionToIndex(player, targetIndex);
      await _syncRealtime(force: true);
      return;
    }

    // Recover an empty queue with a forced request that bypasses retry backoff.
    // Never fall back to index 0, which can replay the current/previous song.
    if (targetIndex >= _queue.length) {
      try {
        await _ensureRecommendations(force: true).timeout(const Duration(seconds: 12));
      } catch (error) {
        _audioLog.warning('Next-track recommendation recovery failed: $error');
      }
      index = player.currentIndex ?? _currentIndex;
      targetIndex = index == null ? -1 : index + 1;
    }
    if (targetIndex >= 0 && targetIndex < _queue.length &&
        targetIndex < (player.sequence?.length ?? 0)) {
      await _transitionToIndex(player, targetIndex);
      await _syncRealtime(force: true);
    } else if (player.hasNext) {
      final nextIndex = player.nextIndex;
      if (nextIndex != null) {
        await _transitionToIndex(player, nextIndex);
        await _syncRealtime(force: true);
      } else {
        await player.seekToNext();
        unawaited(player.play());
      }
    }
  }

  Future<void> previous() async {
    _playSelectionGeneration++;
    if (!_realtime.isPlaybackOwner) {
      await _realtime.sendCommand('previous');
      return;
    }
    if (_manualTransitionInProgress) return;
    final player = await this.player;
    if (player.position > const Duration(seconds: 3)) {
      // Route this through the shared seek path so the explicit seek event is
      // broadcast to the web player and IDE extension as well.
      await seek(Duration.zero);
      return;
    }
    if (player.hasPrevious) {
      final previousIndex = player.previousIndex;
      if (previousIndex != null) {
        await _transitionToIndex(player, previousIndex);
      } else {
        await player.seekToPrevious();
        unawaited(player.play());
      }
      return;
    }

    final targetIndex = _currentIndex == null ? -1 : _currentIndex! - 1;
    if (targetIndex >= 0 && targetIndex < (player.sequence?.length ?? 0)) {
      await _transitionToIndex(player, targetIndex);
    }
  }

  Future<void> _transitionToIndex(AudioPlayer player, int targetIndex) async {
    if (_manualTransitionInProgress || targetIndex < 0 ||
        targetIndex >= (player.sequence?.length ?? 0)) {
      return;
    }

    _manualTransitionInProgress = true;
    try {
      // Never fade the output to silence while a next-track source is loading.
      await player.seek(Duration.zero, index: targetIndex);
      unawaited(player.play().catchError((Object error, StackTrace stack) {
        _audioLog.error('AUDIO transition playback failed: $error');
      }));
    } finally {
      _manualTransitionInProgress = false;
    }
  }

  Future<void> togglePlayback() async {
    if (!_realtime.isPlaybackOwner) {
      await _realtime.sendCommand('toggle');
      return;
    }
    final p = await player;
    if (p.playing) {
      await p.pause();
    } else {
      unawaited(p.play().catchError((Object error, StackTrace stack) {
        _audioLog.error('AUDIO play failed: $error');
      }));
    }
  }

  Future<void> toggleShuffle() async { final player = await this.player; await player.setShuffleModeEnabled(!player.shuffleModeEnabled); }
  Future<void> toggleRepeat() async { final player = await this.player; await player.setLoopMode(player.loopMode == LoopMode.one ? LoopMode.off : LoopMode.one); }

  Future<void> removeFromQueue(int index) async {
    final player = await this.player;
    final playlist = _playlist;
    if (playlist == null || index < 0 || index >= _queue.length || _queue.length == 1) return;
    await playlist.removeAt(index);
    _queue = List.of(_queue)..removeAt(index);
    _queueController.add(List.unmodifiable(_queue));
    _currentIndex = player.currentIndex;
    _currentIndexController.add(_currentIndex);
    unawaited(_syncRealtime(force: true));
    await _syncOriginIsland(force: true);
  }

  /// Reorders only upcoming tracks. The currently playing source is anchored
  /// so a drag operation cannot interrupt playback or change the active song.
  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    final player = await this.player;
    final playlist = _playlist;
    final currentIndex = player.currentIndex ?? _currentIndex;
    if (playlist == null || currentIndex == null ||
        oldIndex <= currentIndex || oldIndex >= _queue.length) {
      return;
    }

    var targetIndex = newIndex;
    if (targetIndex > oldIndex) targetIndex--;
    targetIndex = targetIndex.clamp(currentIndex + 1, _queue.length - 1);
    if (targetIndex == oldIndex) return;

    final reordered = List<Song>.of(_queue);
    final movedSong = reordered.removeAt(oldIndex);
    reordered.insert(targetIndex, movedSong);

    // just_audio updates its sequence index while preserving the active source.
    await playlist.move(oldIndex, targetIndex);
    _queue = reordered;
    _currentIndex = player.currentIndex ?? currentIndex;
    _queueController.add(List.unmodifiable(_queue));
    _currentIndexController.add(_currentIndex);
    unawaited(_syncRealtime(force: true));
  }

  Future<void> _syncRealtime({bool force = false}) async {
    if (_applyingRemoteState || _applyingRemoteCommand) return;
    if (_realtimeSyncJob != null) {
      _realtimeSyncPending = true;
      _realtimeSyncForcePending = _realtimeSyncForcePending || force;
      return;
    }
    _realtimeSyncJob = _sendRealtimeSnapshot(force: force);
    try {
      await _realtimeSyncJob;
    } finally {
      _realtimeSyncJob = null;
      if (_realtimeSyncPending) {
        final pendingForce = _realtimeSyncForcePending;
        _realtimeSyncPending = false;
        _realtimeSyncForcePending = false;
        unawaited(_syncRealtime(force: pendingForce));
      }
    }
  }

  Future<void> _sendRealtimeSnapshot({bool force = false}) async {
    if (_realtime.standaloneMode || _applyingRemoteState || _applyingRemoteCommand || !_realtime.isPlaybackOwner) return;
    if (!force && _lastRemoteSync != null && DateTime.now().difference(_lastRemoteSync!) < const Duration(milliseconds: 350)) return;
    final index = _currentIndex;
    final player = _player;
    final song = index != null && index >= 0 && index < _queue.length ? _queue[index] : null;
    if (player == null) return;
    await _realtime.sync(
      currentSong: song,
      position: player.position,
      duration: player.duration,
      playing: player.playing,
      queue: _queue,
      lyrics: _currentLyricsData?.isSynced == true
          ? _currentLyricsData!.lines
              .where((line) => line.time != null)
              .map((line) {
                final ms = line.time!.inMilliseconds;
                final minutes = ms ~/ 60000;
                final seconds = (ms ~/ 1000) % 60;
                final millis = ms % 1000;
                return '[${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}.${millis.toString().padLeft(3, '0')}]${line.text}';
              })
              .join('\n')
          : _currentLyricsData?.text,
    );
  }

  Song? _songFromRealtime(dynamic value) {
    if (value is! Map) return null;
    final data = Map<String, dynamic>.from(value);
    final id = data['id']?.toString();
    final title = data['title']?.toString();
    final artist = data['artist']?.toString();
    final mediaUrl = data['media_url']?.toString();
    if (id == null || id.isEmpty || title == null || artist == null || mediaUrl == null || mediaUrl.isEmpty) return null;
    return Song(
      id: id,
      title: title,
      artist: artist,
      album: data['album']?.toString(),
      imageUrl: data['image_url']?.toString() ?? '',
      mediaUrl: mediaUrl,
      isrc: data['isrc']?.toString(),
      language: data['language']?.toString(),
      durationSeconds: int.tryParse('${data['duration_seconds'] ?? ''}'),
      tempo: double.tryParse('${data['tempo'] ?? ''}'),
      genre: data['genre']?.toString(),
      lyricsId: data['lyrics_id']?.toString(),
    );
  }

  Future<void> _handleRealtimeState(Map<String, dynamic> state) async {
    if (_applyingRemoteCommand) return;
    if (_applyingRemoteState) {
      final incomingRevision = int.tryParse('${state['revision'] ?? 0}') ?? 0;
      final pendingRevision = int.tryParse('${_pendingRealtimeState?['revision'] ?? 0}') ?? 0;
      if (_pendingRealtimeState == null || incomingRevision >= pendingRevision) {
        _pendingRealtimeState = Map<String, dynamic>.from(state);
      }
      return;
    }
    final revision = int.tryParse('${state['revision'] ?? 0}') ?? 0;
    if (revision > 0 && revision <= _lastRealtimeRevision) return;
    if (revision > 0) _lastRealtimeRevision = revision;
    // The owner is authoritative. Reconnect snapshots must never seek or
    // replace the source that this device is currently playing.
    if (_realtime.isPlaybackOwner) return;
    final remoteTrack = _songFromRealtime(state['track']);
    final remotePlaying = state['playing'] == true;
    final remotePosition = Duration(milliseconds: int.tryParse('${state['position_ms'] ?? 0}') ?? 0);
    final localIndex = _currentIndex;
    final localSong = localIndex != null && localIndex >= 0 && localIndex < _queue.length ? _queue[localIndex] : null;
    final trackChanged = remoteTrack != null && (localSong == null || localSong.id != remoteTrack.id);
    if (!trackChanged && localSong == null && remoteTrack == null) return;

    _lastRemoteSync = DateTime.now();
    _applyingRemoteState = true;
    try {
      final player = await this.player;

      if (!_realtime.isPlaybackOwner) {
        final rawQueue = state['queue'];
        final remoteQueue = rawQueue is List
            ? rawQueue.map(_songFromRealtime).whereType<Song>().toList()
            : <Song>[];
        final remoteIds = remoteQueue.map((song) => song.id).toList();
        final localIds = _queue.map((song) => song.id).toList();
        final queueChanged = remoteQueue.isNotEmpty &&
            (remoteIds.length != localIds.length ||
                List.generate(remoteIds.length, (i) => i >= localIds.length || remoteIds[i] != localIds[i]).any((v) => v));

        if (queueChanged) {
          final isAppend = remoteQueue.length >= _queue.length &&
              List.generate(_queue.length, (i) => _queue[i].id == remoteQueue[i].id).every((same) => same);
          if (isAppend && _playlist != null && _queue.isNotEmpty) {
            final activePlaylist = _playlist!;
            final queueGeneration = _queueGeneration;
            final additions = await _resolveRemoteQueue(remoteQueue.skip(_queue.length).toList());
            if (_realtime.isPlaybackOwner ||
                queueGeneration != _queueGeneration ||
                !identical(_playlist, activePlaylist)) {
              return;
            }
            for (final song in additions) {
              if (_realtime.isPlaybackOwner ||
                  queueGeneration != _queueGeneration ||
                  !identical(_playlist, activePlaylist)) {
                return;
              }
              if (song.mediaUrl.isEmpty) continue;
              await activePlaylist.add(AudioSource.uri(Uri.parse(song.mediaUrl), tag: MediaItem(
                id: song.id, album: song.album ?? 'Loopin',
                title: song.title, artist: song.artist,
                artUri: Uri.tryParse(song.imageUrl),
              )));
              if (_realtime.isPlaybackOwner ||
                  queueGeneration != _queueGeneration ||
                  !identical(_playlist, activePlaylist)) {
                return;
              }
              _queue = [..._queue, song];
            }
            _queueController.add(List.unmodifiable(_queue));
            // The current source remains loaded and playback continues.
            if (trackChanged) {
              final target = _queue.indexWhere((song) => song.id == remoteTrack.id);
              if (target >= 0) await player.seek(remotePosition, index: target);
            }
          } else if (trackChanged) {
            // A different ordered queue is not a reason to reload the active
            // source. Rebuild only when the owner has actually changed tracks.
            final playableQueue = await _resolveRemoteQueue(remoteQueue);
            final targetIndex = playableQueue.indexWhere((song) => song.id == remoteTrack.id);
            if (targetIndex >= 0) {
              final wasPlaying = player.playing;
              await setQueue(playableQueue, initialIndex: targetIndex);
              await player.seek(remotePosition);
              if (wasPlaying || remotePlaying) {
                unawaited(player.play().catchError((Object error, StackTrace stack) {
                  _audioLog.error('AUDIO remote track resume failed: $error');
                }));
              }
            }
          } else {
            // Queue reorder/removal while the current track is unchanged is
            // deferred. Replacing the ConcatenatingAudioSource here interrupts
            // playback; the next authoritative track change reconciles it.
            _audioLog.info('Realtime queue changed while the current track stayed the same; deferring source reconciliation.');
          }
        } else if (trackChanged) {
          final targetIndex = _queue.indexWhere((song) => song.id == remoteTrack.id);
          if (targetIndex >= 0 && targetIndex < (player.sequence?.length ?? 0)) {
            await player.seek(remotePosition, index: targetIndex);
          } else {
            await setQueue([remoteTrack]);
            await player.seek(remotePosition);
          }
        } else if (!player.playing &&
            (player.position - remotePosition).abs() > const Duration(seconds: 4)) {
          // Position snapshots are delayed by transport latency. Never
          // repeatedly seek a playing follower to stale positions.
          await player.seek(remotePosition);
        }

        if (remotePlaying != player.playing) {
          if (remotePlaying) {
            unawaited(player.play().catchError((Object error, StackTrace stack) {
              _audioLog.error('AUDIO play failed: $error');
            }));
          } else {
            await player.pause();
          }
        }
        return;
      }

      if (trackChanged) {
        final targetIndex = _queue.indexWhere((song) => song.id == remoteTrack.id);
        if (targetIndex >= 0 && targetIndex < (player.sequence?.length ?? 0)) {
          await player.seek(remotePosition, index: targetIndex);
        } else {
          await setQueue([remoteTrack]);
          await player.seek(remotePosition);
        }
        if (remotePlaying) {
          unawaited(player.play().catchError((Object error, StackTrace stack) {
              _audioLog.error('AUDIO play failed: $error');
            }));
        } else {
          await player.pause();
        }
        return;
      }

      // Owner state is authoritative; never apply a stale incoming snapshot.
    } finally {
      _applyingRemoteState = false;
      _drainPendingRealtimeUpdates();
    }
  }

  Future<void> _waitForPlaybackStart(AudioPlayer player) async {
    if (player.playing) return;
    await player.playingStream.firstWhere((playing) => playing).timeout(
      const Duration(seconds: 10),
      onTimeout: () => throw TimeoutException('Playback did not start within 10 seconds.'),
    );
  }

  void _handleRealtimeCommandResult(Map<String, dynamic> result) {
    if (result['success'] == true) return;
    _audioLog.warning("Realtime command failed (request ${result['request_id'] ?? 'unknown'}): ${result['error'] ?? 'Unknown error'}");
  }

  Future<void> _handleRealtimePlaybackEvent(Map<String, dynamic> event) async {
    if (_realtime.isPlaybackOwner || _applyingRemoteCommand) return;
    if (_applyingRemoteState) {
      final queued = Map<String, dynamic>.from(event);
      if (queued['event'] == 'seek') {
        _pendingRealtimePlaybackEvents.removeWhere((item) =>
            item['event'] == 'seek' && item['track_id'] == queued['track_id']);
      }
      _pendingRealtimePlaybackEvents.add(queued);
      return;
    }
    final eventType = event['event']?.toString();
    final eventTrackId = event['track_id']?.toString();
    final index = _currentIndex;
    final localTrackId = index != null && index >= 0 && index < _queue.length ? _queue[index].id : null;
    // A track transition snapshot may still be in transit. Do not consume the
    // event revision until its matching track has been applied locally.
    if (eventTrackId != null && eventTrackId != localTrackId) {
      if (event['_defer_once'] != true) {
        final deferred = Map<String, dynamic>.from(event)..['_defer_once'] = true;
        _pendingRealtimePlaybackEvents.add(deferred);
      }
      return;
    }
    final revision = int.tryParse('${event['revision'] ?? 0}') ?? 0;
    if (revision > 0 && revision <= _lastRealtimeRevision) return;
    if (revision > 0) _lastRealtimeRevision = revision;

    final activePlayer = await player;
    _applyingRemoteState = true;
    try {
      switch (eventType) {
        case 'play':
          if (!activePlayer.playing) {
            unawaited(activePlayer.play().catchError((Object error, StackTrace stack) {
              _audioLog.error('AUDIO synchronized play failed: $error');
            }));
          }
          break;
        case 'pause':
          if (activePlayer.playing) await activePlayer.pause();
          break;
        case 'seek':
          final requested = int.tryParse('${event['position_ms'] ?? 0}') ?? 0;
          final duration = activePlayer.duration?.inMilliseconds;
          final target = requested.clamp(0, duration ?? requested).toInt();
          await activePlayer.seek(Duration(milliseconds: target));
          break;
      }
    } finally {
      _applyingRemoteState = false;
      _drainPendingRealtimeUpdates();
    }
  }

  void _drainPendingRealtimeUpdates() {
    if (_applyingRemoteState || _applyingRemoteCommand || _realtime.isPlaybackOwner) return;
    final pendingState = _pendingRealtimeState;
    if (pendingState != null) {
      _pendingRealtimeState = null;
      unawaited(_handleRealtimeState(pendingState));
      return;
    }
    if (_pendingRealtimePlaybackEvents.isNotEmpty) {
      final nextEvent = _pendingRealtimePlaybackEvents.removeAt(0);
      unawaited(_handleRealtimePlaybackEvent(nextEvent));
    }
  }

  Future<void> _handleRealtimeLyrics(String? trackId, String? lyrics) async {
    if (lyrics == null || lyrics.isEmpty) return;
    if (trackId != null && _currentIndex != null && _currentIndex! >= 0 && _currentIndex! < _queue.length && _queue[_currentIndex!].id != trackId) return;
    _lastRemoteSync = DateTime.now();
  }

  Future<void> _handleRealtimeQueue(List<Map<String, dynamic>> remoteQueue) async {
    if (remoteQueue.isEmpty || _applyingRemoteState) return;
    final songs = remoteQueue.map(_songFromRealtime).toList();
    if (songs.any((song) => song == null)) return;
    final remoteSongs = songs.whereType<Song>().toList();
    // A queue notification must never replace the owner's audio source.
    if (_realtime.isPlaybackOwner) return;
    final localIds = _queue.map((song) => song.id).toList();
    final remoteIdsBeforeResolve = remoteSongs.map((song) => song.id).toList();
    if (remoteIdsBeforeResolve.length >= localIds.length &&
        List.generate(localIds.length, (i) => localIds[i] == remoteIdsBeforeResolve[i]).every((v) => v)) {
      // The owner appended tracks. Extend the playlist without calling
      // setAudioSource, which would interrupt the currently playing song.
      final additions = remoteSongs.skip(localIds.length).toList();
      if (additions.isEmpty) {
        return;
      }
      final playlist = _playlist;
      if (playlist == null) {
        return;
      }
      final queueGeneration = _queueGeneration;
      final resolvedAdditions = await _resolveRemoteQueue(additions);
      if (_realtime.isPlaybackOwner ||
          queueGeneration != _queueGeneration ||
          !identical(_playlist, playlist)) {
          return;
        }
      for (final song in resolvedAdditions) {
        if (_realtime.isPlaybackOwner ||
            queueGeneration != _queueGeneration ||
            !identical(_playlist, playlist)) {
          return;
        }
        if (song.mediaUrl.isEmpty) continue;
        await playlist.add(AudioSource.uri(Uri.parse(song.mediaUrl), tag: MediaItem(
          id: song.id, album: song.album ?? 'Loopin',
          title: song.title, artist: song.artist,
          artUri: Uri.tryParse(song.imageUrl),
        )));
        if (_realtime.isPlaybackOwner ||
            queueGeneration != _queueGeneration ||
            !identical(_playlist, playlist)) {
          return;
        }
        _queue = [..._queue, song];
      }
      _queueController.add(List.unmodifiable(_queue));
      return;
    }
    // Full queue replacement can interrupt a playing source. This handler
    // therefore applies append-only updates; a new current track is reconciled
    // by the authoritative player_state handler.
    return;
  }

  Future<void> _handleRealtimeCommand(String command, Map<String, dynamic> payload) async {
    if (!_realtime.isPlaybackOwner) {
      throw StateError('This device is no longer the active playback owner.');
    }
    final previousCommand = _remoteCommandJob;
    final commandDone = Completer<void>();
    _remoteCommandJob = commandDone.future;
    try {
      await previousCommand;
      if (!_realtime.isPlaybackOwner) {
        throw StateError('Playback ownership changed before the command could run.');
      }
      await _applyRealtimeCommand(command, payload);
    } finally {
      commandDone.complete();
    }
  }

  Future<void> _applyRealtimeCommand(String command, Map<String, dynamic> payload) async {
    if (!_realtime.isPlaybackOwner) {
      throw StateError('This device is no longer the active playback owner.');
    }
    _applyingRemoteCommand = true;
    try {
      final player = await this.player;
      switch (command) {
        case 'play':
          if (!player.playing) {
            final started = _waitForPlaybackStart(player);
            unawaited(player.play().catchError((Object error, StackTrace stack) {
              _audioLog.error('AUDIO play failed: $error');
            }));
            await started;
          }
          break;
        case 'pause':
          await player.pause();
          break;
        case 'toggle':
          if (player.playing) {
            await player.pause();
          } else {
            final started = _waitForPlaybackStart(player);
            unawaited(player.play().catchError((Object error, StackTrace stack) {
              _audioLog.error('AUDIO toggle play failed: $error');
            }));
            await started;
          }
          break;
        case 'next': {
          final previousIndex = player.currentIndex;
          await next();
          if (player.currentIndex != previousIndex && !player.playing) {
            await _waitForPlaybackStart(player);
          }
          break;
        }
        case 'previous': {
          final previousIndex = player.currentIndex;
          await previous();
          if (player.currentIndex != previousIndex && !player.playing) {
            await _waitForPlaybackStart(player);
          }
          break;
        }
        case 'seek':
          final duration = player.duration;
          final requested = int.tryParse('${payload['position_ms'] ?? 0}') ?? 0;
          final target = requested.clamp(0, duration?.inMilliseconds ?? requested).toInt();
          await player.seek(Duration(milliseconds: target));
          break;
        case 'append_track':
          final raw = payload['track'];
          if (raw is! Map) throw StateError('The requested track payload is missing or invalid.');
          final data = Map<String, dynamic>.from(raw);
          final trackId = data['id']?.toString() ?? '';
          final trackTitle = data['title']?.toString() ?? '';
          if (trackId.isEmpty || trackTitle.isEmpty) throw StateError('The requested track is missing its ID or title.');
          final track = Song(
            id: trackId, title: trackTitle,
            artist: data['artist']?.toString() ?? 'Unknown Artist',
            album: data['album']?.toString(), imageUrl: data['image_url']?.toString() ?? '',
            mediaUrl: '', isrc: data['isrc']?.toString(),
            language: data['language']?.toString(), genre: data['genre']?.toString(),
            durationSeconds: int.tryParse('${data['duration_seconds'] ?? ''}'),
            tempo: double.tryParse('${data['tempo'] ?? ''}'),
            lyricsId: data['lyrics_id']?.toString(),
          );
          final streamUrl = await _resolvePlaybackUrl(track, quality: _audioSettings.quality);
          if (streamUrl == null || streamUrl.isEmpty) throw StateError('Could not resolve the requested track.');
          await appendSongToQueue(Song(
            id: track.id, title: track.title, artist: track.artist,
            album: track.album, imageUrl: track.imageUrl, mediaUrl: streamUrl,
            isrc: track.isrc, language: track.language, durationSeconds: track.durationSeconds,
            tempo: track.tempo, genre: track.genre, lyricsId: track.lyricsId,
          ));
          break;
        case 'play_track':
          final raw = payload['track'];
          if (raw is! Map) {
            throw StateError('The requested track payload is missing or invalid.');
          }
          final track = Map<String, dynamic>.from(raw);
          final id = track['id']?.toString() ?? '';
          final title = track['title']?.toString() ?? '';
          if (id.isEmpty || title.isEmpty) {
            throw StateError('The requested track is missing its ID or title.');
          }
          final existingIndex = _queue.indexWhere((song) => song.id == id);
          if (existingIndex >= 0) {
            await playAtIndex(existingIndex);
            await _waitForPlaybackStart(player);
            break;
          }
          await playSong(Song(
            id: id,
            title: title,
            artist: track['artist']?.toString() ?? 'Unknown Artist',
            album: track['album']?.toString(),
            imageUrl: track['image_url']?.toString() ?? '',
            mediaUrl: track['media_url']?.toString() ?? '',
            language: track['language']?.toString(),
            genre: track['genre']?.toString(),
            durationSeconds: int.tryParse('${track['duration'] ?? track['duration_seconds'] ?? ''}'),
            tempo: double.tryParse('${track['tempo'] ?? ''}'),
          ));
          await _waitForPlaybackStart(player);
          break;
      }
    } finally {
      _applyingRemoteCommand = false;
    }
    if (command == 'seek') {
      final index = _currentIndex;
      final trackId = index != null && index >= 0 && index < _queue.length ? _queue[index].id : null;
      unawaited(_realtime.publishPlaybackEvent('seek', positionMs: _player?.position.inMilliseconds ?? 0, trackId: trackId));
    }
    if (command == 'next' || command == 'previous' || command == 'play' || command == 'pause' || command == 'seek' || command == 'toggle' || command == 'play_track' || command == 'append_track') {
      // Remote commands are state transitions. Publish the resulting player
      // state immediately instead of waiting for the normal 350ms throttle;
      // otherwise the web client can briefly keep rendering the old track.
      unawaited(_syncRealtime(force: true));
    }
  }

  Future<void> _syncOriginIsland({bool force = false}) async {
    if (_queue.isEmpty || _currentIndex == null) return;
    final now = DateTime.now();
    if (!force && _lastOriginIslandUpdate != null &&
        now.difference(_lastOriginIslandUpdate!) < const Duration(seconds: 2)) {
      return;
    }
    final index = _currentIndex!;
    if (index < 0 || index >= _queue.length) return;
    final player = _player;
    if (player == null) return;
    _lastOriginIslandUpdate = now;
    final song = _queue[index];
    await OriginIslandService.update(
      mediaId: song.id,
      title: song.title,
      artist: song.artist,
      position: player.position,
      duration: player.duration,
      isPlaying: player.playing,
      artworkUrl: song.imageUrl,
    );
    await HomeWidgetService.updateNowPlaying(
      title: song.title,
      artist: song.artist,
      isPlaying: player.playing,
    );
  }

  Future<void> _fetchLyricsForWidget(Song song) async {
    _currentLyricsSongId = song.id;
    _currentLyricsData = null;
    _lastWidgetLyricIndex = null;
    try {
      final data = await _lyricsService.fetch(song);
      if (_currentLyricsSongId == song.id) {
        _currentLyricsData = data;
        _updateWidgetLyricsLine();
        final lyricsText = data.isSynced
            ? data.lines
                .where((line) => line.time != null)
                .map((line) {
                  final ms = line.time!.inMilliseconds;
                  final minutes = ms ~/ 60000;
                  final seconds = (ms ~/ 1000) % 60;
                  final millis = ms % 1000;
                  return '[${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}.${millis.toString().padLeft(3, '0')}] ${line.text}';
                })
                .join('\n')
            : data.text;
        if (lyricsText.trim().isNotEmpty) {
          unawaited(_realtime.publishLyrics(song.id, lyricsText));
        }
      }
    } catch (_) {
      if (_currentLyricsSongId == song.id) {
        unawaited(HomeWidgetService.updateLyrics(
          song: '${song.title} · ${song.artist}',
          text: 'Enjoy music on Loopin',
        ));
      }
    }
  }

  void _updateWidgetLyricsLine() {
    final song = (_currentIndex != null && _currentIndex! >= 0 && _currentIndex! < _queue.length)
        ? _queue[_currentIndex!]
        : null;
    if (song == null) return;
    final data = _currentLyricsData;
    if (data == null || data.lines.isEmpty) {
      if (_lastWidgetLyricIndex == null) {
        _lastWidgetLyricIndex = 0;
        unawaited(HomeWidgetService.updateLyrics(
          song: '${song.title} · ${song.artist}',
          text: 'Playing on Loopin',
        ));
      }
      return;
    }

    if (!data.isSynced) {
      if (_lastWidgetLyricIndex == null) {
        _lastWidgetLyricIndex = 0;
        final preview = data.text.split('\n').where((l) => l.trim().isNotEmpty).take(4).join('\n');
        unawaited(HomeWidgetService.updateLyrics(
          song: '${song.title} · ${song.artist}',
          text: preview.isNotEmpty ? preview : data.text,
        ));
      }
      return;
    }

    final pos = _player?.position ?? Duration.zero;
    int? active;
    for (var i = 0; i < data.lines.length; i++) {
      final line = data.lines[i];
      if (line.time != null && line.time! <= pos) {
        active = i;
      } else if (line.time != null && line.time! > pos) {
        break;
      }
    }

    if (active != null && active != _lastWidgetLyricIndex) {
      _lastWidgetLyricIndex = active;
      final currentLine = data.lines[active].text.trim();
      final nextLine = (active + 1 < data.lines.length) ? data.lines[active + 1].text.trim() : '';
      final textToShow = nextLine.isNotEmpty ? '$currentLine\n$nextLine' : currentLine;
      unawaited(HomeWidgetService.updateLyrics(
        song: '${song.title} · ${song.artist}',
        text: textToShow.isNotEmpty ? textToShow : '♪',
      ));
    }
  }


  /// Append a host-approved Listen Together suggestion without replacing the
  /// currently playing source or resetting its playhead.
  Future<void> appendSongToQueue(Song song) async {
    if (!_realtime.isPlaybackOwner) {
      await _realtime.sendAppendTrack({
        'id': song.id, 'title': song.title, 'artist': song.artist,
        'album': song.album, 'image_url': song.imageUrl,
        'language': song.language, 'genre': song.genre,
        'duration_seconds': song.durationSeconds, 'tempo': song.tempo,
        'lyrics_id': song.lyricsId, 'isrc': song.isrc,
      });
      return;
    }
    final activePlayer = await player;
    final playlist = _playlist;
    if (playlist == null || activePlayer.audioSource == null) {
      await playSong(song);
      return;
    }
    if (_queue.any((item) => item.id == song.id)) return;
    final playable = song.mediaUrl.isNotEmpty ? song : Song(
      id: song.id, title: song.title, artist: song.artist,
      album: song.album, imageUrl: song.imageUrl, mediaUrl: song.mediaUrl,
      isrc: song.isrc, language: song.language, durationSeconds: song.durationSeconds,
      tempo: song.tempo, genre: song.genre, lyricsId: song.lyricsId,
    );
    await playlist.add(AudioSource.uri(
      Uri.parse(playable.mediaUrl),
      tag: MediaItem(
        id: playable.id, album: playable.album ?? 'Loopin',
        title: playable.title, artist: playable.artist,
        artUri: Uri.tryParse(playable.imageUrl),
      ),
    ));
    _queue = [..._queue, playable];
    _queueController.add(List.unmodifiable(_queue));
    unawaited(_syncRealtime(force: true));
  }

  void dispose() {
    _backgroundSyncTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_realtime.dispose());
    _indexSubscription?.cancel();
    _playerStateSubscription?.cancel();
    _playbackEventSubscription?.cancel();
    _positionSubscription?.cancel();
    _audioSessionSubscription?.cancel();
    unawaited(OriginIslandService.clear());
    unawaited(HomeWidgetService.updateNowPlaying(
      title: 'Nothing Playing',
      artist: 'Tap to open Loopin',
      isPlaying: false,
    ));
    unawaited(HomeWidgetService.updateLyrics(
      song: 'No Song Playing',
      text: 'Play a song with lyrics to see live verses right on your home screen.',
    ));
    _monochrome.dispose();
    _queueController.close();
    _currentIndexController.close();
    _player?.dispose();
  }
}
