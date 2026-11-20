import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/song.dart';
import 'debug_log_service.dart';
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
    final cleanTitle = TrackNormalizer.normalizeTitle(song.title);
    final cleanArtist = TrackNormalizer.primaryArtist(song.artist);

    // LRCLIB provides timed and plain lyrics without requiring a backend.
    try {
      final exact = await _fetchLrclib(cleanTitle, cleanArtist, song.durationSeconds);
      if (exact != null && exact.lines.isNotEmpty) {
        _lyricsLog.success('Lyrics fetched from LRCLIB (synced=${exact.isSynced}) for: ${song.title}');
        return exact;
      }
    } catch (error) {
      _lyricsLog.info('LRCLIB lookup failed: $error');
    }

    for (final query in [
      '${song.title} ${song.artist}',
      '$cleanTitle $cleanArtist',
      cleanTitle,
    ]) {
      if (query.trim().isEmpty) continue;
      try {
        final result = await _searchLrclib(query);
        if (result != null && result.lines.isNotEmpty) {
          _lyricsLog.success('Lyrics fetched from LRCLIB search for: ${song.title}');
          return result;
        }
      } catch (error) {
        _lyricsLog.info('LRCLIB search failed: $error');
      }
    }

    try {
      final fallback = await _fetchLyricsOvh(cleanArtist, cleanTitle);
      if (fallback != null && fallback.lines.isNotEmpty) {
        _lyricsLog.success('Lyrics fetched from Lyrics.ovh for: ${song.title}');
        return fallback;
      }
    } catch (error) {
      _lyricsLog.info('Lyrics.ovh lookup failed: $error');
    }

    throw StateError('Lyrics are not available for "${song.title}".');
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
