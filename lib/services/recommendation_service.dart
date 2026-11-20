import 'dart:convert';

import '../models/song.dart';
import 'app_storage.dart';
import 'debug_log_service.dart';
import 'monochrome_api.dart';
import 'track_normalizer.dart';

final _recommendationLog = LoopinDebugLogService.instance;

/// On-device recommendation engine inspired by Monochrome's smart seed and
/// listening-signal model. No Loopin/Django endpoint is required.
class RecommendationService {
  static final RecommendationService _instance = RecommendationService._internal();
  factory RecommendationService() => _instance;
  RecommendationService._internal();

  final AppStorage _storage = AppStorage();
  final MonochromeApi _api = MonochromeApi();
  static const _historyKey = 'loopin_v2_listening_history';
  static const _likesKey = 'loopin_v2_liked_songs';
  static const _dislikesKey = 'loopin_v2_disliked_tracks';
  static const _dislikedArtistsKey = 'loopin_v2_disliked_artists';
  static const _signalsKey = 'loopin_v2_track_signals';
  final Set<String> _likedIds = {};
  final Set<String> _dislikedIds = {};
  final Set<String> _dislikedArtists = {};
  final Map<String, Map<String, dynamic>> _signals = {};
  bool _loaded = false;

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    try {
      final likes = await _storage.read(key: _likesKey);
      if (likes != null) {
        final rows = jsonDecode(likes);
        if (rows is List) {
          for (final row in rows.whereType<Map>()) {
            final song = Song.fromJson(Map<String, dynamic>.from(row));
            if (song.id.isNotEmpty) _likedIds.add(song.id);
          }
        }
      }
      final dislikes = await _storage.read(key: _dislikesKey);
      if (dislikes != null) {
        final rows = jsonDecode(dislikes);
        if (rows is List) _dislikedIds.addAll(rows.map((e) => e.toString()));
      }
      final artists = await _storage.read(key: _dislikedArtistsKey);
      if (artists != null) {
        final rows = jsonDecode(artists);
        if (rows is List) _dislikedArtists.addAll(rows.map((e) => e.toString()));
      }
      final signals = await _storage.read(key: _signalsKey);
      if (signals != null) {
        final decoded = jsonDecode(signals);
        if (decoded is Map) {
          decoded.forEach((key, value) {
            if (value is Map) _signals[key.toString()] = Map<String, dynamic>.from(value);
          });
        }
      }
    } catch (error) {
      _recommendationLog.warning('Could not restore local music preferences: $error');
    }
    _loaded = true;
  }

  Future<void> _saveSignals() async {
    await _storage.write(key: _signalsKey, value: jsonEncode(_signals));
  }

  Future<List<Map<String, dynamic>>> _history() async {
    final raw = await _storage.read(key: _historyKey);
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw);
      return decoded is List
          ? decoded.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
          : [];
    } catch (_) {
      return [];
    }
  }

  void recordPlay(Song song) {
    _recordSignal(song, 'play');
  }

  void recordCompletion(Song song) {
    _recordSignal(song, 'complete');
  }

  void recordSkip(Song song, {required Duration listened}) {
    _recordSignal(song, 'skip', position: listened.inSeconds);
  }

  void recordQueueGenerated(Iterable<Song> songs) {}

  Future<void> _recordSignal(Song song, String event, {int position = 0}) async {
    await _ensureLoaded();
    if (song.id.isEmpty) return;
    final signal = _signals.putIfAbsent(song.id, () => {
      'plays': 0, 'completions': 0, 'skips': 0, 'listened_seconds': 0,
    });
    if (event == 'play') signal['plays'] = (signal['plays'] as int) + 1;
    if (event == 'complete') signal['completions'] = (signal['completions'] as int) + 1;
    if (event == 'skip') {
      signal['skips'] = (signal['skips'] as int) + 1;
      signal['listened_seconds'] = (signal['listened_seconds'] as int) + position;
    }
    signal['last_event'] = event;
    signal['updated_at'] = DateTime.now().millisecondsSinceEpoch;
    await _saveSignals();

    if (event == 'play') {
      final history = await _history();
      history.insert(0, {
        ...song.toJson(),
        'played_at': DateTime.now().millisecondsSinceEpoch,
      });
      if (history.length > 500) history.removeRange(500, history.length);
      await _storage.write(key: _historyKey, value: jsonEncode(history));
    }
  }

  Future<List<Song>> buildRecommendations(
    Song current, {
    int limit = 30,
    Iterable<Song> currentQueue = const [],
    Iterable<Song> candidates = const [],
  }) async {
    await _ensureLoaded();
    final excluded = <String>{current.id, ...currentQueue.map((s) => s.id)};
    final history = await _history();
    for (final row in history.take(35)) {
      final id = row['id']?.toString() ?? '';
      if (id.isNotEmpty) excluded.add(id);
    }

    final likedSeeds = await loadLikedSongs();
    final historySeeds = await loadHistory(limit: 25);
    final seeds = <Song>[current, ...likedSeeds.take(12), ...historySeeds.take(20)];

    final queries = <String>{};
    for (final seed in seeds) {
      if (seed.artist.trim().length >= 2) queries.add(seed.artist.trim());
      if ((seed.genre ?? '').trim().length >= 2) queries.add(seed.genre!.trim());
      if ((seed.language ?? '').trim().length >= 2) queries.add(seed.language!.trim());
      if (seed.title.trim().length >= 2) queries.add(seed.title.trim());
      if (queries.length >= 10) break;
    }

    final fetched = <Song>[];
    for (final query in queries) {
      try {
        fetched.addAll(await _api.search(query, pages: 1, limit: 30));
      } catch (error) {
        _recommendationLog.warning('Recommendation discovery failed for "$query": $error');
      }
    }
    fetched.addAll(candidates);

    final unique = <String, Song>{};
    for (final candidate in fetched) {
      if (candidate.id.isEmpty || excluded.contains(candidate.id)) continue;
      if (_dislikedIds.contains(candidate.id)) continue;
      final artistKey = candidate.artist.toLowerCase().trim();
      if (_dislikedArtists.contains(artistKey)) continue;
      unique.putIfAbsent(candidate.id, () => candidate);
    }

    final ranked = unique.values.map((song) => (
      song: song,
      score: _score(song, current) +
          likedSeeds
              .map((seed) => _score(song, seed) * 0.65)
              .fold<double>(0, (a, b) => a > b ? a : b) +
          historySeeds
              .take(12)
              .map((seed) => _score(song, seed) * 0.35)
              .fold<double>(0, (a, b) => a > b ? a : b),
    )).toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    final result = <Song>[];
    final artistCounts = <String, int>{};
    for (final entry in ranked) {
      if (result.length >= limit.clamp(1, 50)) break;
      final artist = entry.song.artist.toLowerCase().trim();
      final count = artistCounts[artist] ?? 0;
      if (count >= 3) continue;
      artistCounts[artist] = count + 1;
      result.add(entry.song);
    }
    _recommendationLog.success('Local smart queue ranked ${result.length} tracks from ${unique.length} candidates.');
    return result;
  }

  double _score(Song candidate, Song current) {
    var score = 0.0;
    final artist = candidate.artist.toLowerCase();
    if (artist == current.artist.toLowerCase()) score += 2;
    if (candidate.language != null && current.language != null &&
        candidate.language!.toLowerCase() == current.language!.toLowerCase()) score += 3;
    if (candidate.genre != null && current.genre != null &&
        candidate.genre!.toLowerCase() == current.genre!.toLowerCase()) score += 2;
    if (candidate.tempo != null && current.tempo != null) {
      final delta = (candidate.tempo! - current.tempo!).abs();
      score += delta <= 8 ? 2 : delta <= 20 ? 1 : 0;
    }
    if (candidate.durationSeconds != null && current.durationSeconds != null) {
      final delta = (candidate.durationSeconds! - current.durationSeconds!).abs();
      score += delta <= 12 ? 1 : 0;
    }
    final signal = _signals[candidate.id];
    if (signal != null) {
      score += ((signal['completions'] as num?)?.toDouble() ?? 0) * 0.2;
      score -= ((signal['skips'] as num?)?.toDouble() ?? 0) * 1.5;
    }
    if (TrackNormalizer.isDuplicate(candidate, current)) score -= 10;
    return score;
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
    await _ensureLoaded();
    setLikeLocally(song.id, liked);
    final history = await _storage.read(key: _likesKey);
    final rows = <Song>[];
    if (history != null) {
      try {
        final decoded = jsonDecode(history);
        if (decoded is List) {
          rows.addAll(decoded.whereType<Map>().map((e) => Song.fromJson(Map<String, dynamic>.from(e))));
        }
      } catch (_) {}
    }
    rows.removeWhere((item) => item.id == song.id);
    if (liked) rows.insert(0, song);
    await _storage.write(key: _likesKey, value: jsonEncode(rows.map((e) => e.toJson()).toList()));
  }

  Future<bool> toggleLike(Song song) async {
    final liked = !isLiked(song.id);
    await syncLike(song, liked);
    return liked;
  }

  Future<Set<String>> loadLikedIds() async {
    await _ensureLoaded();
    return Set<String>.from(_likedIds);
  }

  Future<List<Song>> loadLikedSongs() async {
    await _ensureLoaded();
    final raw = await _storage.read(key: _likesKey);
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw);
      return decoded is List
          ? decoded.whereType<Map>().map((e) => Song.fromJson(Map<String, dynamic>.from(e))).toList()
          : [];
    } catch (_) {
      return [];
    }
  }

  Future<List<Song>> loadHistory({int limit = 200}) async {
    final rows = await _history();
    return rows.take(limit).map((row) => Song.fromJson(row)).toList();
  }

  Future<void> recordLike(Song song) async => syncLike(song, true);

  Future<void> recordDislike(Song song) async {
    await _ensureLoaded();
    _dislikedIds.add(song.id);
    _dislikedArtists.add(song.artist.toLowerCase().trim());
    await _storage.write(key: _dislikesKey, value: jsonEncode(_dislikedIds.toList()));
    await _storage.write(key: _dislikedArtistsKey, value: jsonEncode(_dislikedArtists.toList()));
  }
}
