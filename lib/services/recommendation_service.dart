import '../models/song.dart';
import 'debug_log_service.dart';
import 'auth_service.dart';
import 'service_config_service.dart';

final _recommendationLog = LoopinDebugLogService.instance;

class RecommendationService {
  static final RecommendationService _instance = RecommendationService._internal();
  final AuthService _backend = AuthService();
  final ServiceConfigService _services = ServiceConfigService();
  final Set<String> _likedIds = {};

  factory RecommendationService() => _instance;
  RecommendationService._internal();

  void recordPlay(Song song) {
    _sendEvent(song, 'play');
  }

  void recordCompletion(Song song) {
    _sendEvent(song, 'complete');
  }

  void recordSkip(Song song, {required Duration listened}) {
    _sendEvent(song, 'skip', position: listened.inSeconds.toDouble());
  }

  /// The backend now owns recommendation filtering. Flutter only reports which
  /// songs are currently in the local playback queue and consumes the already
  /// filtered queue returned by Django.
  void recordQueueGenerated(Iterable<Song> songs) {
    for (final song in songs) {
      if (song.id.isEmpty) continue;
      _sendEvent(song, 'queue_generate');
    }
    _recommendationLog.info('Recorded generated queue songs for backend filtering');
  }

  Future<List<Song>> buildRecommendations(
    Song current, {
    int limit = 30,
    Iterable<Song> currentQueue = const [],
    Iterable<Song> candidates = const [],
  }) async {
    if (!await _services.enabled('recommendations')) return const [];

    final queue = <Song>[];
    final seenIds = <String>{};

    for (final song in currentQueue) {
      if (song.id.isEmpty || seenIds.contains(song.id)) continue;
      seenIds.add(song.id);
      queue.add(song);
    }

    // Keep the request bounded during long listening sessions. Django also
    // blocks recently generated songs from listening history, so the complete
    // lifetime queue does not need to be sent on every refill request.
    if (queue.length > 120) {
      queue.removeRange(0, queue.length - 120);
    }

    final payload = {
      'current': _songPayload(current),
      'queue': queue.map(_songPayload).toList(),
      'candidates': candidates.map(_songPayload).toList(),
      'limit': limit.clamp(1, 50).toInt(),
    };

    Map<String, dynamic> response;
    try {
      response = await _backend.post('/recommendations/next/', payload);
    } on AuthException catch (error) {
      // A stale/expired access token must not leave guest playback with an
      // empty queue. Retry this public endpoint without credentials; valid
      // tokens still use the personalized authenticated response above.
      if (error.statusCode != 401) rethrow;
      _recommendationLog.warning(
        'Recommendation auth expired; retrying public discovery without credentials.',
      );
      response = await _backend.post(
        '/recommendations/next/',
        payload,
        authenticated: false,
      );
    }

    final raw = (response['queue'] ?? response['recommendations']) as List? ?? const [];
    final result = <Song>[];

    for (final item in raw.whereType<Map>()) {
      final song = Song(
        id: item['id']?.toString() ?? '',
        title: item['title']?.toString() ?? '',
        artist: item['artist']?.toString() ?? 'Unknown Artist',
        album: item['album']?.toString(),
        imageUrl: item['imageUrl']?.toString() ?? item['image_url']?.toString() ?? '',
        mediaUrl: item['media_url']?.toString() ?? '',
        language: item['language']?.toString(),
        durationSeconds: int.tryParse(item['duration']?.toString() ?? ''),
        tempo: double.tryParse(item['tempo']?.toString() ?? ''),
        genre: item['genre']?.toString() ?? item['category']?.toString(),
      );
      if (song.id.isNotEmpty && song.title.isNotEmpty) result.add(song);
    }

    _recommendationLog.success('Backend filtered queue: ${result.length} songs');
    return result;
  }

  Map<String, dynamic> _songPayload(Song song) => {
    'id': song.id,
    'title': song.title,
    'artist': song.artist,
    'album': song.album ?? '',
    'language': song.language ?? '',
    'duration': song.durationSeconds ?? 0,
    'tempo': song.tempo ?? 0,
    'genre': song.genre ?? '',
  };

  Future<void> _sendEvent(Song song, String type, {double position = 0}) async {
    if (!await _services.enabled('listening_sync')) return;
    try {
      await _backend.post('/listening/events/', {
        'song_id': song.id, 'title': song.title, 'artist': song.artist,
        'album': song.album ?? '', 'event_type': type,
        'position_seconds': position, 'duration_seconds': song.durationSeconds ?? 0,
        'metadata': {'image_url': song.imageUrl, 'language': song.language ?? '', 'tempo': song.tempo ?? 0, 'genre': song.genre ?? ''},
      });
    } catch (_) {}
  }

  bool isLiked(String songId) => _likedIds.contains(songId);

  void setLikeLocally(String songId, bool liked) {
    if (liked) {
      _likedIds.add(songId);
    } else {
      _likedIds.remove(songId);
    }
  }

  Future<void> syncLike(Song song, bool liked) async {
    if (!await _services.enabled('listening_sync')) {
      throw StateError(await _services.message('listening_sync'));
    }
    try {
      final response = await _backend.post('/listening/likes/', {
        'song_id': song.id, 'title': song.title, 'artist': song.artist,
        'album': song.album ?? '', 'image_url': song.imageUrl,
        'metadata': {'language': song.language ?? '', 'genre': song.genre ?? '', 'tempo': song.tempo ?? 0},
      });
      final serverLiked = response['liked'] == true;
      if (serverLiked != liked) {
        throw StateError('The server returned an unexpected like state.');
      }
      setLikeLocally(song.id, serverLiked);
    } catch (error) {
      throw StateError(error.toString());
    }
  }

  Future<bool> toggleLike(Song song) async {
    final liked = !isLiked(song.id);
    setLikeLocally(song.id, liked);
    try {
      await syncLike(song, liked);
      return liked;
    } catch (error) {
      setLikeLocally(song.id, !liked);
      throw StateError(error.toString());
    }
  }

  Future<Set<String>> loadLikedIds() async {
    try {
      final response = await _backend.get('/listening/likes/');
      final ids = (response['likes'] as List? ?? const []).whereType<Map>()
          .map((item) => item['song_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty).toSet();
      _likedIds..clear()..addAll(ids);
    } catch (_) {}
    return Set<String>.from(_likedIds);
  }

  Future<List<Song>> loadLikedSongs() async {
    final response = await _backend.get('/listening/likes/');
    return (response['likes'] as List? ?? const []).whereType<Map>().map((item) => Song(
      id: item['song_id']?.toString() ?? '', title: item['title']?.toString() ?? '',
      artist: item['artist']?.toString() ?? 'Unknown Artist', album: item['album']?.toString(),
      imageUrl: item['image_url']?.toString() ?? '', mediaUrl: '',
    )).where((song) => song.id.isNotEmpty).toList();
  }

  Future<void> recordLike(Song song) => toggleLike(song).then((_) {});

  Future<void> recordDislike(Song song) async {
    if (!await _services.enabled('listening_sync')) throw StateError(await _services.message('listening_sync'));
    await _backend.post('/listening/events/', {
      'song_id': song.id, 'title': song.title, 'artist': song.artist,
      'album': song.album ?? '', 'event_type': 'dislike',
      'position_seconds': 0, 'duration_seconds': song.durationSeconds ?? 0,
      'metadata': {'image_url': song.imageUrl, 'language': song.language ?? '', 'genre': song.genre ?? '', 'tempo': song.tempo ?? 0},
    });
  }

}
