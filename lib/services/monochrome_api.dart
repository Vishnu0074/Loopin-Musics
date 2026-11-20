import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/song.dart';
import 'debug_log_service.dart';

/// Flutter client for Monochrome's open-source Tracks Streamer API.
///
/// Search metadata and stream resolution both use the Tracks Streamer contract:
/// GET /search/tracks?q=...&limit=... and GET /track/{trackId}.
class MonochromeApi {
  static const String baseUrl = String.fromEnvironment(
    'MONOCHROME_TRACKS_API',
    defaultValue: 'https://tracks.monochrome.st',
  );

  final http.Client _client;
  final Map<String, List<Song>> _searchCache = {};
  final Map<String, String?> _streamCache = {};
  final Set<String> _nativeTrackIds = {};
  final Map<String, Future<List<Song>>> _inFlight = {};
  final LoopinDebugLogService _log = LoopinDebugLogService.instance;

  MonochromeApi({http.Client? client}) : _client = client ?? http.Client();

  Future<List<Song>> search(
    String query, {
    int pages = 2,
    int limit = 20,
  }) async {
    final clean = query.trim();
    if (clean.isEmpty) return const [];
    final requested = (pages * limit).clamp(1, 100).toInt();
    return searchPage(clean, page: 1, limit: requested);
  }

  /// The Tracks Streamer API exposes a bounded result limit rather than a
  /// page token. Fetching page N therefore requests N * limit results and
  /// slices the requested window locally, keeping the API contract compatible.
  Future<List<Song>> searchPage(
    String query, {
    int page = 1,
    int limit = 20,
  }) async {
    final clean = query.trim();
    if (clean.isEmpty) return const [];
    final safePage = page.clamp(1, 100).toInt();
    final safeLimit = limit.clamp(1, 100).toInt();
    final totalLimit = (safePage * safeLimit).clamp(1, 100).toInt();
    final all = await _searchTracks(clean, totalLimit);
    final start = (safePage - 1) * safeLimit;
    if (start >= all.length) return const [];
    return all.skip(start).take(safeLimit).toList(growable: false);
  }

  Future<List<Song>> _searchTracks(String query, int limit) {
    final key = '${query.toLowerCase()}::$limit';
    final cached = _searchCache[key];
    if (cached != null) return Future.value(cached);
    final pending = _inFlight[key];
    if (pending != null) return pending;

    final request = _fetchTracks(query, limit);
    _inFlight[key] = request;
    return request.whenComplete(() { _inFlight.remove(key); });
  }

  Future<List<Song>> _fetchTracks(String query, int limit) async {
    final uri = Uri.parse('$baseUrl/search/tracks').replace(
      queryParameters: {'q': query, 'limit': '$limit'},
    );
    final response = await _getWithRetry(uri);
    if (response.statusCode != 200) {
      throw Exception('Monochrome search failed (HTTP ${response.statusCode}).');
    }

    final decoded = jsonDecode(response.body);
    final root = decoded is Map ? Map<String, dynamic>.from(decoded) : <String, dynamic>{};
    final rawTracks = root['tracks'] is List
        ? root['tracks'] as List
        : root['items'] is List
            ? root['items'] as List
            : const [];

    final songs = <Song>[];
    final seen = <String>{};
    for (final raw in rawTracks) {
      if (raw is! Map) continue;
      final song = _normalizeTrack(Map<String, dynamic>.from(raw));
      if (song == null || !seen.add(song.id)) continue;
      _nativeTrackIds.add(song.id);
      songs.add(song);
    }
    _searchCache['${query.toLowerCase()}::$limit'] = songs;
    if (_searchCache.length > 80) _searchCache.remove(_searchCache.keys.first);
    _log.success('MONOCHROME search: ${songs.length} tracks for "$query"');
    return songs;
  }

  Future<http.Response> _getWithRetry(Uri uri) async {
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final response = await _client
            .get(uri, headers: const {'Accept': 'application/json'})
            .timeout(const Duration(seconds: 18));
        if ((response.statusCode == 502 ||
                response.statusCode == 503 ||
                response.statusCode == 504) &&
            attempt < 2) {
          await Future<void>.delayed(Duration(milliseconds: 250 * (attempt + 1)));
          continue;
        }
        return response;
      } catch (error) {
        lastError = error;
        if (attempt == 2) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 250 * (attempt + 1)));
      }
    }
    throw Exception('Unable to reach Monochrome Tracks Streamer: $lastError');
  }

  Song? _normalizeTrack(Map<String, dynamic> item) {
    String firstString(Iterable<dynamic> values) {
      for (final value in values) {
        final text = value?.toString().trim() ?? '';
        if (text.isNotEmpty && text.toLowerCase() != 'null') return text;
      }
      return '';
    }

    final id = firstString([item['trackId'], item['id']]);
    final title = firstString([item['title'], item['name']]);
    if (id.isEmpty || title.isEmpty) return null;

    final artists = item['artists'] is List ? item['artists'] as List : const [];
    final artistNames = <String>[];
    for (final artist in artists) {
      if (artist is Map) {
        final name = firstString([artist['name'], artist['displayName']]);
        if (name.isNotEmpty) artistNames.add(name);
      }
    }
    final rawArtistNames = item['artistNames'];
    if (artistNames.isEmpty && rawArtistNames is List) {
      artistNames.addAll(rawArtistNames.map((value) => value.toString()).where((value) => value.trim().isNotEmpty));
    }
    final artist = firstString([
      artistNames.isNotEmpty ? artistNames.join(', ') : null,
      item['artist'],
      item['artistName'],
      item['primaryArtist'],
    ]);
    final album = firstString([item['albumTitle'], item['releaseTitle'], item['album'] is Map ? item['album']['title'] : item['album']]);
    final artwork = firstString([item['artwork'], item['cover'], item['image'], item['thumbnail']]);
    final durationRaw = item['duration'];
    final durationValue = durationRaw is num ? durationRaw.toDouble() : double.tryParse(durationRaw?.toString() ?? '');
    final duration = durationValue == null
        ? null
        : (durationValue > 1000 ? (durationValue / 1000).round() : durationValue.round());

    return Song(
      id: id,
      title: title,
      artist: artist.isEmpty ? 'Unknown Artist' : artist,
      album: album.isEmpty ? null : album,
      imageUrl: artwork,
      mediaUrl: '$baseUrl/track/${Uri.encodeComponent(id)}',
      isrc: firstString([item['isrc'], item['isrcCode']]).isEmpty ? null : firstString([item['isrc'], item['isrcCode']]),
      language: firstString([item['language']]).isEmpty ? null : firstString([item['language']]),
      durationSeconds: duration,
      tempo: (item['tempo'] ?? item['bpm']) is num
          ? ((item['tempo'] ?? item['bpm']) as num).toDouble()
          : double.tryParse((item['tempo'] ?? item['bpm'])?.toString() ?? ''),
      genre: firstString([item['genre'], item['category']]).isEmpty ? null : firstString([item['genre'], item['category']]),
      lyricsId: firstString([item['lyricsId'], item['lyrics_id']]).isEmpty ? null : firstString([item['lyricsId'], item['lyrics_id']]),
    );
  }

  Future<String?> resolveStream(Song song, {String quality = 'auto'}) async {
    final cached = _streamCache[song.id];
    if (cached != null) return cached;

    final supplied = Uri.tryParse(song.mediaUrl);
    if (supplied != null && (supplied.scheme == 'https' || supplied.scheme == 'http')) {
      if (_nativeTrackIds.contains(song.id) || song.mediaUrl.contains('/track/')) {
        _streamCache[song.id] = song.mediaUrl;
        return song.mediaUrl;
      }
    }

    // A result originating from Tracks Streamer can be streamed directly.
    if (_nativeTrackIds.contains(song.id) || song.id.startsWith('tracks:')) {
      final id = song.id.replaceFirst(RegExp(r'^tracks:(?:track:)?'), '');
      final url = '$baseUrl/track/${Uri.encodeComponent(id)}';
      _streamCache[song.id] = url;
      return url;
    }

    // Resolve imported/external metadata to a matching Tracks Streamer ID.
    final query = '${song.artist} ${song.title}'.trim();
    if (query.isEmpty) return null;
    try {
      final candidates = await _searchTracks(query, 12);
      Song? best;
      var bestScore = 0;
      for (final candidate in candidates) {
        final score = _scoreCandidate(candidate, song);
        if (score > bestScore) {
          bestScore = score;
          best = candidate;
        }
      }
      if (best == null || bestScore < 85) {
        _streamCache[song.id] = null;
        return null;
      }
      final url = '$baseUrl/track/${Uri.encodeComponent(best.id)}';
      _streamCache[song.id] = url;
      return url;
    } catch (error) {
      _log.warning('MONOCHROME stream resolution failed for ${song.title}: $error');
      return null;
    }
  }

  int _scoreCandidate(Song candidate, Song target) {
    final targetIsrc = (target.isrc ?? '').trim().toLowerCase();
    final candidateIsrc = (candidate.isrc ?? '').trim().toLowerCase();
    if (targetIsrc.isNotEmpty && targetIsrc == candidateIsrc) return 200;

    String clean(String value) {
      final lower = value.toLowerCase()
          .replaceAll(RegExp(r'\b(feat|featuring|ft)\.?\s+.*$'), '')
          .replaceAll(RegExp(r'[\(\[\{].*?[\)\]\}]'), '');
      final latin = lower.replaceAll(RegExp(r'[^a-z0-9]'), '');
      // Keep non-Latin scripts intact (Malayalam, Tamil, Arabic, etc.).
      return latin.isNotEmpty
          ? latin
          : lower.replaceAll(RegExp(r'[\s.,!?;:(){}\[\]/_-]+'), '');
    }

    final targetTitle = clean(target.title);
    final candidateTitle = clean(candidate.title);
    var score = 0;
    if (targetTitle == candidateTitle && targetTitle.isNotEmpty) {
      score += 100;
    } else if (targetTitle.isNotEmpty &&
        candidateTitle.isNotEmpty &&
        (targetTitle.contains(candidateTitle) || candidateTitle.contains(targetTitle))) {
      score += 65;
    }

    final targetArtists = clean(target.artist);
    final candidateArtists = clean(candidate.artist);
    if (targetArtists.isNotEmpty &&
        candidateArtists.isNotEmpty &&
        (candidateArtists.contains(targetArtists) || targetArtists.contains(candidateArtists))) {
      score += 50;
    }

    final targetDuration = target.durationSeconds ?? 0;
    final candidateDuration = candidate.durationSeconds ?? 0;
    if (targetDuration > 0 && candidateDuration > 0) {
      final difference = (targetDuration - candidateDuration).abs();
      if (difference <= 3) {
        score += 25;
      } else if (difference <= 7) {
        score += 10;
      }
    }
    return score;
  }

  Future<String?> fetchLyricsId(String songId) async => null;

  void clearCache() {
    _searchCache.clear();
    _streamCache.clear();
    _nativeTrackIds.clear();
    _inFlight.clear();
  }

  void dispose() => _client.close();
}
), '')
          .replaceAll(RegExp(r'[\\(\\[\\{].*?[\\)\\]\\}]'), '');
      final latin = lower.replaceAll(RegExp(r'[^a-z0-9]'), '');
      // Keep non-Latin scripts intact (e.g. Malayalam, Tamil, Arabic) rather
      // than reducing a valid title or artist to an empty match key.
      return latin.isNotEmpty
          ? latin
          : lower.replaceAll(RegExp(r'[\\s.,!?;:(){}\\[\\]\\-_/]+'), '');
    }

    final targetTitle = clean(target.title);
    final candidateTitle = clean(candidate.title);
    var score = 0;
    if (targetTitle == candidateTitle && targetTitle.isNotEmpty) {
      score += 100;
    } else if (targetTitle.isNotEmpty &&
        (targetTitle.contains(candidateTitle) || candidateTitle.contains(targetTitle))) {
      score += 65;
    }

    final targetArtists = clean(target.artist);
    final candidateArtists = clean(candidate.artist);
    if (targetArtists.isNotEmpty &&
        (candidateArtists.contains(targetArtists) || targetArtists.contains(candidateArtists))) {
      score += 50;
    }
    final targetDuration = target.durationSeconds ?? 0;
    final candidateDuration = candidate.durationSeconds ?? 0;
    if (targetDuration > 0 && candidateDuration > 0) {
      final difference = (targetDuration - candidateDuration).abs();
      if (difference <= 3) {
        score += 25;
      } else if (difference <= 7) {
        score += 10;
      }
    }
    return score;
  }

  Future<String?> fetchLyricsId(String songId) async => null;

  void clearCache() {
    _searchCache.clear();
    _streamCache.clear();
    _nativeTrackIds.clear();
    _inFlight.clear();
  }

  void dispose() => _client.close();
}
