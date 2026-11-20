import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/song.dart';
import 'debug_log_service.dart';
import 'monochrome_api.dart';
import 'auth_service.dart';
import 'track_normalizer.dart';

final _lyricsLog = LoopinDebugLogService.instance;

class LyricLine {
  final Duration? time;
  final String text;

  const LyricLine({
    this.time,
    required this.text,
  });

  bool get hasTime => time != null;
}

class LyricsData {
  final String text;
  final List<LyricLine> lines;
  final bool isSynced;
  final String? copyright;
  final String? source;
  final String? language;

  const LyricsData({
    required this.text,
    required this.lines,
    this.isSynced = false,
    this.copyright,
    this.source,
    this.language,
  });
}

class LyricsService {
  static const _jioSaavnBaseUrl = 'https://www.jiosaavn.com/api.php';
  final MonochromeApi _api = MonochromeApi();
  static final Map<String, LyricsData> _cache = {};
  static final Map<String, Future<LyricsData>> _inFlight = {};

  static LyricsData? getCached(Song song) {
    final key = TrackNormalizer.trackFamilyKey(song);
    return _cache[song.id] ?? _cache[key];
  }

  static void preload(Song song) {
    LyricsService().fetch(song).ignore();
  }

  static void preloadQueue(List<Song> songs, [int currentIndex = 0]) {
    if (songs.isEmpty) return;
    if (currentIndex >= 0 && currentIndex < songs.length) {
      preload(songs[currentIndex]);
    }
    if (currentIndex + 1 < songs.length) {
      preload(songs[currentIndex + 1]);
    }
    if (currentIndex + 2 < songs.length) {
      preload(songs[currentIndex + 2]);
    }
  }

  Future<LyricsData> fetch(Song song) async {
    final key = TrackNormalizer.trackFamilyKey(song);
    if (_cache.containsKey(song.id)) return _cache[song.id]!;
    if (_cache.containsKey(key)) return _cache[key]!;

    if (_inFlight.containsKey(song.id)) return _inFlight[song.id]!;
    if (_inFlight.containsKey(key)) return _inFlight[key]!;

    final future = _fetchInternal(song);
    _inFlight[song.id] = future;
    _inFlight[key] = future;

    try {
      final data = await future;
      _cache[song.id] = data;
      _cache[key] = data;
      return data;
    } finally {
      _inFlight.remove(song.id);
      _inFlight.remove(key);
    }
  }

  Future<LyricsData> _fetchInternal(Song song) async {
    if (kIsWeb) {
      final query = Uri(queryParameters: {
        'title': song.title,
        'artist': song.artist,
        if ((song.album ?? '').isNotEmpty) 'album': song.album!,
        if (song.durationSeconds != null) 'duration': song.durationSeconds.toString(),
      }).query;
      final response = await AuthService().get('/listening/lyrics/?$query');
      final synced = response['syncedLyrics']?.toString() ?? '';
      final plain = response['plainLyrics']?.toString() ?? '';
      final text = synced.isNotEmpty ? synced : plain;
      if (text.trim().isEmpty) {
        throw StateError('Lyrics are not available for "${song.title}".');
      }
      return LyricsData(
        text: text,
        lines: synced.isNotEmpty ? parseLrc(synced) : _parseLines(plain),
        isSynced: synced.isNotEmpty,
        source: response['source']?.toString() ?? 'LRCLIB',
        language: null,
      );
    }

    final cleanTitle = TrackNormalizer.normalizeTitle(song.title);
    final cleanArtist = TrackNormalizer.primaryArtist(song.artist);

    // 1. Try JioSaavn official lyrics (Direct, ID lookup, or search)
    try {
      final jioData = await _fetchJioSaavn(song, cleanTitle, cleanArtist);
      if (jioData != null && jioData.lines.isNotEmpty) {
        _lyricsLog.success('Lyrics fetched from JioSaavn for: ${song.title} (${jioData.language ?? "native"})');
        return jioData;
      }
    } catch (e) {
      _lyricsLog.info('JioSaavn lyrics lookup failed: $e');
    }

    // 2. Try LRCLIB API with exact track metadata (Open Database with Synced timestamps)
    try {
      final lrclibData = await _fetchLrclib(cleanTitle, cleanArtist, song.durationSeconds);
      if (lrclibData != null && lrclibData.lines.isNotEmpty) {
        _lyricsLog.success('Lyrics fetched from LRCLIB (synced=${lrclibData.isSynced}) for: ${song.title}');
        return lrclibData;
      }
    } catch (e) {
      _lyricsLog.info('LRCLIB lyrics lookup failed: $e');
    }

    // 3. Try LRCLIB search queries (full title/artist and cleaned title/artist)
    for (final q in [
      '${song.title} ${song.artist}',
      '$cleanTitle $cleanArtist',
      cleanTitle,
    ]) {
      try {
        final searchData = await _searchLrclib(q);
        if (searchData != null && searchData.lines.isNotEmpty) {
          _lyricsLog.success('Lyrics fetched from LRCLIB Search ("$q") for: ${song.title}');
          return searchData;
        }
      } catch (e) {
        _lyricsLog.info('LRCLIB Search ("$q") lookup failed: $e');
      }
    }

    // 4. Try Saavn Dev API fallback for Indian language regional tracks
    try {
      final saavnDevData = await _fetchSaavnDev(song, cleanTitle, cleanArtist);
      if (saavnDevData != null && saavnDevData.lines.isNotEmpty) {
        _lyricsLog.success('Lyrics fetched from Saavn Dev for: ${song.title}');
        return saavnDevData;
      }
    } catch (e) {
      _lyricsLog.info('Saavn Dev lookup failed: $e');
    }

    // 5. Try lyrics.ovh fallback
    try {
      final ovhData = await _fetchLyricsOvh(cleanArtist, cleanTitle);
      if (ovhData != null && ovhData.lines.isNotEmpty) {
        _lyricsLog.success('Lyrics fetched from Lyrics.ovh for: ${song.title}');
        return ovhData;
      }
    } catch (e) {
      _lyricsLog.info('Lyrics.ovh lookup failed: $e');
    }

    throw StateError('Lyrics are not available for "${song.title}".');
  }

  Future<LyricsData?> _fetchJioSaavn(Song song, String cleanTitle, String cleanArtist) async {
    var lyricsId = song.lyricsId;
    if (lyricsId == null || lyricsId.trim().isEmpty) {
      lyricsId = await _api.fetchLyricsId(song.id);
    }

    // If lyricsId is still null, try finding the track on JioSaavn
    if (lyricsId == null || lyricsId.trim().isEmpty) {
      lyricsId = await _searchJioSaavnLyricsId('$cleanTitle $cleanArtist');
    }

    final targetId = (lyricsId != null && lyricsId.trim().isNotEmpty) ? lyricsId : song.id;
    if (targetId.trim().isEmpty) return null;

    final uri = Uri.parse(_jioSaavnBaseUrl).replace(queryParameters: {
      '__call': 'lyrics.getLyrics',
      'lyrics_id': targetId,
      'ctx': 'web6dot0',
      'api_version': '4',
      '_format': 'json',
      '_marker': '0',
      'cc': 'in',
    });

    final response = await http
        .get(uri, headers: const {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'})
        .timeout(const Duration(seconds: 8));

    if (response.statusCode != 200) return null;

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) return null;

    final root = Map<String, dynamic>.from(decoded);
    final rawLyrics = root['lyrics'];
    String text = '';
    String? copyright;
    String? language;

    if (rawLyrics is String) {
      text = rawLyrics;
    } else if (rawLyrics is Map) {
      final lyricsMap = Map<String, dynamic>.from(rawLyrics);
      text = _firstText(lyricsMap, [
        'lyrics', 'text', 'lyrics_text', 'lyrics_html', 'lyrics_body', 'snippet',
      ]);
      copyright = lyricsMap['copyright']?.toString();
      language = lyricsMap['language']?.toString();
    }

    if (text.trim().isEmpty) {
      text = _firstText(root, [
        'lyrics_text', 'lyrics_html', 'lyrics_body', 'text', 'lyrics_snippet',
      ]);
      copyright ??= root['copyright']?.toString();
      language ??= root['language']?.toString();
    }

    if (text.trim().isEmpty && root['data'] is Map) {
      final dataMap = Map<String, dynamic>.from(root['data'] as Map);
      text = _firstText(dataMap, [
        'lyrics', 'lyrics_text', 'lyrics_html', 'text',
      ]);
      copyright ??= dataMap['copyright']?.toString();
      language ??= dataMap['language']?.toString();
    }

    text = _clean(text);
    if (text.isEmpty) return null;

    final lines = _parseLines(text);
    if (lines.isEmpty) return null;

    return LyricsData(
      text: text,
      lines: lines,
      isSynced: false,
      copyright: copyright != null && copyright.trim().isNotEmpty ? _clean(copyright) : null,
      source: 'JioSaavn',
      language: language,
    );
  }

  Future<String?> _searchJioSaavnLyricsId(String query) async {
    try {
      final uri = Uri.parse(_jioSaavnBaseUrl).replace(queryParameters: {
        '__call': 'autocomplete.get',
        'query': query,
        '_format': 'json',
        '_marker': '0',
        'ctx': 'web6dot0',
        'api_version': '4',
      });
      final res = await http.get(uri, headers: const {'User-Agent': 'Mozilla/5.0'}).timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) return null;
      final decoded = jsonDecode(res.body);
      if (decoded is! Map) return null;
      final songs = decoded['songs'] is Map ? (decoded['songs']['data'] as List?) : null;
      if (songs == null || songs.isEmpty) return null;
      for (final item in songs) {
        if (item is Map) {
          final more = item['more_info'] is Map ? Map<String, dynamic>.from(item['more_info'] as Map) : null;
          final lid = item['lyrics_id']?.toString() ?? more?['lyrics_id']?.toString();
          if (lid != null && lid.isNotEmpty && lid != 'null') return lid;
          final hasLyrics = item['has_lyrics']?.toString() ?? more?['has_lyrics']?.toString();
          if (hasLyrics == 'true') {
            final id = item['id']?.toString();
            if (id != null && id.isNotEmpty) return id;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  Future<LyricsData?> _fetchSaavnDev(Song song, String cleanTitle, String cleanArtist) async {
    try {
      final uri = Uri.parse('https://saavn.dev/api/songs/${song.id}/lyrics');
      final res = await http.get(uri).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        if (decoded is Map && decoded['data'] is Map) {
          final data = Map<String, dynamic>.from(decoded['data'] as Map);
          final rawLyrics = data['lyrics']?.toString() ?? '';
          final text = _clean(rawLyrics);
          if (text.isNotEmpty) {
            return LyricsData(
              text: text,
              lines: _parseLines(text),
              isSynced: false,
              copyright: data['copyright']?.toString(),
              source: 'JioSaavn',
            );
          }
        }
      }
    } catch (_) {}
    return null;
  }

  Future<LyricsData?> _fetchLrclib(String title, String artist, int? durationSeconds) async {
    if (title.isEmpty) return null;

    final queryParams = {
      'track_name': title,
      if (artist.isNotEmpty) 'artist_name': artist,
      if (durationSeconds != null && durationSeconds > 0) 'duration': durationSeconds.toString(),
    };

    final uri = Uri.https('lrclib.net', '/api/get', queryParams);
    final response = await http
        .get(uri, headers: const {'User-Agent': 'Loopin/1.0.0 (https://loopin.app)'})
        .timeout(const Duration(seconds: 8));

    if (response.statusCode != 200) return null;

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) return null;

    final syncedLyrics = decoded['syncedLyrics']?.toString();
    if (syncedLyrics != null && syncedLyrics.trim().isNotEmpty) {
      final lines = parseLrc(syncedLyrics);
      if (lines.isNotEmpty) {
        final plainText = _clean(lines.map((l) => l.text).join('\n'));
        return LyricsData(
          text: plainText,
          lines: lines,
          isSynced: true,
          copyright: 'Provided by LRCLIB Open Database',
          source: 'LRCLIB Synced',
        );
      }
    }

    final plainLyrics = decoded['plainLyrics']?.toString();
    if (plainLyrics != null && plainLyrics.trim().isNotEmpty) {
      final text = _clean(plainLyrics);
      return LyricsData(
        text: text,
        lines: _parseLines(text),
        isSynced: false,
        copyright: 'Provided by LRCLIB Open Database',
        source: 'LRCLIB',
      );
    }

    return null;
  }

  Future<LyricsData?> _searchLrclib(String query) async {
    final clean = query.trim();
    if (clean.isEmpty) return null;

    final uri = Uri.https('lrclib.net', '/api/search', {'q': clean});
    final response = await http
        .get(uri, headers: const {'User-Agent': 'Loopin/1.0.0 (https://loopin.app)'})
        .timeout(const Duration(seconds: 8));

    if (response.statusCode != 200) return null;

    final decoded = jsonDecode(response.body);
    if (decoded is! List || decoded.isEmpty) return null;

    // Prefer synced lyrics first from search results
    for (final item in decoded) {
      if (item is! Map) continue;
      final synced = item['syncedLyrics']?.toString();
      if (synced != null && synced.trim().isNotEmpty) {
        final lines = parseLrc(synced);
        if (lines.isNotEmpty) {
          final plainText = _clean(lines.map((l) => l.text).join('\n'));
          return LyricsData(
            text: plainText,
            lines: lines,
            isSynced: true,
            copyright: 'Provided by LRCLIB Open Database',
            source: 'LRCLIB Synced',
          );
        }
      }
    }

    // Fallback to plain lyrics
    for (final item in decoded) {
      if (item is! Map) continue;
      final plain = item['plainLyrics']?.toString();
      if (plain != null && plain.trim().isNotEmpty) {
        final text = _clean(plain);
        return LyricsData(
          text: text,
          lines: _parseLines(text),
          isSynced: false,
          copyright: 'Provided by LRCLIB Open Database',
          source: 'LRCLIB',
        );
      }
    }

    return null;
  }

  Future<LyricsData?> _fetchLyricsOvh(String artist, String title) async {
    if (artist.isEmpty || title.isEmpty) return null;

    final uri = Uri.https('api.lyrics.ovh', '/v1/$artist/$title');
    final response = await http
        .get(uri, headers: const {'User-Agent': 'Mozilla/5.0'})
        .timeout(const Duration(seconds: 8));

    if (response.statusCode != 200) return null;

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) return null;

    final lyrics = decoded['lyrics']?.toString();
    if (lyrics != null && lyrics.trim().isNotEmpty) {
      final text = _clean(lyrics);
      return LyricsData(
        text: text,
        lines: _parseLines(text),
        isSynced: false,
        copyright: 'Provided by Lyrics.ovh',
        source: 'Lyrics.ovh',
      );
    }

    return null;
  }

  /// Parses LRC formatted synchronized timestamps [mm:ss.xx]
  static List<LyricLine> parseLrc(String lrcContent) {
    final lines = <LyricLine>[];
    final rawLines = lrcContent.split(RegExp(r'\r?\n'));
    final timeRegex = RegExp(r'\[(\d{2}):(\d{2})(?:\.(\d{1,3}))?\]');

    for (final raw in rawLines) {
      final line = raw.trim();
      if (line.isEmpty) continue;

      final matches = timeRegex.allMatches(line);
      if (matches.isNotEmpty) {
        final text = TrackNormalizer.unescapeHtml(
          line.replaceAll(timeRegex, '').trim(),
        );
        if (text.isEmpty) continue;

        for (final m in matches) {
          final minutes = int.tryParse(m.group(1) ?? '0') ?? 0;
          final seconds = int.tryParse(m.group(2) ?? '0') ?? 0;
          var millis = 0;
          final msStr = m.group(3);
          if (msStr != null) {
            if (msStr.length == 1) {
              millis = (int.tryParse(msStr) ?? 0) * 100;
            } else if (msStr.length == 2) {
              millis = (int.tryParse(msStr) ?? 0) * 10;
            } else {
              millis = int.tryParse(msStr) ?? 0;
            }
          }
          final duration = Duration(
            minutes: minutes,
            seconds: seconds,
            milliseconds: millis,
          );
          lines.add(LyricLine(time: duration, text: text));
        }
      } else {
        final cleaned = TrackNormalizer.unescapeHtml(line);
        if (cleaned.isNotEmpty && !cleaned.startsWith('[al:') && !cleaned.startsWith('[ar:') && !cleaned.startsWith('[ti:')) {
          lines.add(LyricLine(time: null, text: cleaned));
        }
      }
    }

    if (lines.any((l) => l.time != null)) {
      lines.sort((a, b) {
        if (a.time == null && b.time == null) return 0;
        if (a.time == null) return 1;
        if (b.time == null) return -1;
        return a.time!.compareTo(b.time!);
      });
    }

    return lines;
  }

  static List<LyricLine> _parseLines(String plainText) {
    return plainText
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .map((l) => LyricLine(time: null, text: l))
        .toList();
  }

  String _firstText(Map<String, dynamic> map, Iterable<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value is String && value.trim().isNotEmpty) return value;
    }
    return '';
  }

  String _clean(String value) {
    var cleaned = TrackNormalizer.unescapeHtml(value);
    cleaned = cleaned
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&#039;', "'")
        .trim();
    return cleaned;
  }
}
