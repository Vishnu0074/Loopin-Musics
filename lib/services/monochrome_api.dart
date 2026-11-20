import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:dart_des/dart_des.dart';
import 'package:http/http.dart' as http;
import '../models/song.dart';
import 'auth_service.dart';
import 'debug_log_service.dart';
import 'track_normalizer.dart';

final _debugLog = LoopinDebugLogService.instance;

class MonochromeApi {
  static const _baseUrl = 'https://www.jiosaavn.com/api.php';
  static const _jioSaavnDesKey = '38346591';

  Future<List<Song>> search(String query, {int pages = 2, int limit = 20}) async {
    final clean = query.trim();
    if (clean.isEmpty) return const [];
    final results = <Song>[];
    final seen = <String>{};
    for (var page = 1; page <= pages; page++) {
      final songs = await searchPage(clean, page: page, limit: limit);
      for (final song in songs) {
        if (seen.add(song.id)) results.add(song);
      }
    }
    return results;
  }

  Future<List<Song>> searchPage(String query, {int page = 1, int limit = 20}) async {
    final stopwatch = Stopwatch()..start();
    final clean = query.trim();
    if (clean.isEmpty) return const [];

    if (kIsWeb) {
      return _searchWebPage(clean, page: page, limit: limit);
    }

    try {
      final uri = Uri.parse(_baseUrl).replace(queryParameters: {
        '__call': 'search.getResults',
        'q': clean,
        'n': limit.clamp(1, 50).toString(),
        'p': page.toString(),
        '_format': 'json',
        '_marker': '0',
        'cc': 'in',
        'ctx': 'web6dot0',
        'api_version': '4',
      });
      final response = await http.get(uri, headers: const {'User-Agent': 'Mozilla/5.0'});
      if (response.statusCode != 200) {
        throw Exception('JioSaavn search HTTP ${response.statusCode}');
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) throw const FormatException('JioSaavn search response is not an object');
      final node = decoded['results'];
      final rawResults = node is List
          ? node
          : decoded['songs'] is Map && decoded['songs']['data'] is List
              ? decoded['songs']['data'] as List
              : const [];

      final songs = <Song>[];
      final seen = <String>{};
      for (final raw in rawResults) {
        if (raw is! Map) continue;
        final item = Map<String, dynamic>.from(raw);
        final id = _string(item, 'id');
        final title = _firstString(item, ['song', 'title', 'name']);
        if (id.isEmpty || title.isEmpty || !seen.add(id)) continue;
        final more = item['more_info'] is Map
            ? Map<String, dynamic>.from(item['more_info'] as Map)
            : <String, dynamic>{};
        final artist = _firstString(item, ['primary_artists', 'singers', 'artist', 'subtitle']);
        final album = _firstString(item, ['album']).isNotEmpty
            ? _firstString(item, ['album'])
            : _string(more, 'album');

        final encrypted = _firstString(more, ['encrypted_media_url', 'encrypted_media_path', 'encrypted_url']).isNotEmpty
            ? _firstString(more, ['encrypted_media_url', 'encrypted_media_path', 'encrypted_url'])
            : _firstString(item, ['encrypted_media_url', 'encrypted_media_path', 'encrypted_url']);
        var mediaUrl = '';
        if (encrypted.isNotEmpty) {
          final decrypted = _decryptMediaUrl(encrypted);
          if (_isHttpUrl(decrypted)) {
            mediaUrl = _selectQuality(decrypted, 'auto', _string(more, '320kbps').toLowerCase() == 'true');
          }
        }
        if (mediaUrl.isEmpty) {
          mediaUrl = _firstHttpUrl([_string(more, 'media_preview_url'), _string(more, 'vlink'), _string(item, 'media_preview_url')]) ?? '';
        }

        songs.add(Song(
          id: id,
          title: title,
          artist: artist.isEmpty ? 'Unknown Artist' : artist,
          album: album.isEmpty ? null : album,
          isrc: _firstString(item, ['isrc', 'isrc_code']).isNotEmpty
              ? _firstString(item, ['isrc', 'isrc_code'])
              : _firstString(more, ['isrc', 'isrc_code']),
          imageUrl: _highResArtwork(_firstString(item, ['image'])),
          mediaUrl: mediaUrl,
          language: _firstString(item, ['language']).isNotEmpty
              ? _firstString(item, ['language'])
              : _string(more, 'language'),
          durationSeconds: int.tryParse(_firstString(item, ['duration']).isNotEmpty
              ? _firstString(item, ['duration'])
              : _string(more, 'duration')),
          tempo: double.tryParse(_firstString(item, ['tempo']).isNotEmpty
              ? _firstString(item, ['tempo'])
              : _firstString(more, ['tempo', 'bpm'])),
          genre: _firstString(item, ['genre', 'genres', 'category']).isNotEmpty
              ? _firstString(item, ['genre', 'genres', 'category'])
              : _firstString(more, ['genre', 'genres', 'category']),
          lyricsId: _firstString(item, ['lyrics_id']).isNotEmpty
              ? _firstString(item, ['lyrics_id'])
              : _string(more, 'lyrics_id'),
        ));
      }
      _debugLog.success('JIOSAAVN SEARCH page=$page parsed ${songs.length} songs in ${stopwatch.elapsedMilliseconds}ms');
      return songs;
    } finally {
      stopwatch.stop();
    }
  }

  Future<List<Song>> _searchWebPage(String query, {required int page, required int limit}) async {
    final response = await AuthService().get(
      '/catalog/music/search/?q=${Uri.encodeQueryComponent(query)}&page=$page&limit=$limit',
      authenticated: false,
    );
    final rows = response['results'];
    if (rows is! List) return const [];
    return rows.whereType<Map>().map((raw) {
      final item = Map<String, dynamic>.from(raw);
      return Song(
        id: _string(item, 'id'),
        title: _string(item, 'title'),
        artist: _string(item, 'artist').isEmpty ? 'Unknown Artist' : _string(item, 'artist'),
        album: _string(item, 'album').isEmpty ? null : _string(item, 'album'),
        isrc: _firstString(item, ['isrc', 'isrc_code']),
        lyricsId: _string(item, 'lyrics_id'),
        imageUrl: _highResArtwork(_string(item, 'image_url').isNotEmpty ? _string(item, 'image_url') : _string(item, 'imageUrl')),
        mediaUrl: _string(item, 'media_url'),
        durationSeconds: int.tryParse(_string(item, 'duration')),
        language: _string(item, 'language'),
        tempo: double.tryParse(_string(item, 'tempo')),
        genre: _string(item, 'genre').isNotEmpty ? _string(item, 'genre') : _string(item, 'category'),
      );
    }).where((song) => song.id.isNotEmpty && song.title.isNotEmpty).toList();
  }

  Future<String?> resolveStream(Song song, {String quality = 'auto'}) async {
    // Search and recommendation responses already carry a resolved direct provider
    // URL. Reuse it on every platform, unless it is a backend proxy stream URL with
    // an ephemeral or expired token.
    if (_isHttpUrl(song.mediaUrl) && !song.mediaUrl.contains('/catalog/music/stream/')) {
      final safeUrl = song.mediaUrl.startsWith('http://')
          ? song.mediaUrl.replaceFirst('http://', 'https://')
          : song.mediaUrl;
      return _selectQuality(
        safeUrl,
        quality,
        safeUrl.contains('_320'),
      );
    }

    // On web, resolve missing URLs through our same-origin catalog endpoint.
    if (kIsWeb && song.id.trim().isNotEmpty) {
      try {
        final response = await AuthService().get(
          '/catalog/music/stream/${Uri.encodeComponent(song.id)}/',
          authenticated: false,
        );
        final url = _string(response, 'media_url');
        if (_isHttpUrl(url)) return url;
      } catch (error) {
        _debugLog.warning('Catalog stream resolution failed: $error');
      }
      return null;
    }

    try {
      if (song.id.trim().isNotEmpty) {
        final uri = Uri.parse(_baseUrl).replace(queryParameters: {
          '__call': 'song.getDetails',
          'pids': song.id,
          '_format': 'json',
          '_marker': '0',
          'cc': 'in',
          'ctx': 'web6dot0',
          'api_version': '4',
        });
        final response = await http.get(uri, headers: const {'User-Agent': 'Mozilla/5.0'});
        if (response.statusCode == 200) {
          final decoded = jsonDecode(response.body);
          if (decoded is Map) {
            final songs = decoded['songs'];
            Map? rawSong;
            if (songs is List && songs.isNotEmpty && songs.first is Map) {
              rawSong = songs.first as Map;
            } else if (songs is Map && songs.isNotEmpty) {
              rawSong = songs.values.firstWhere((v) => v is Map, orElse: () => null) as Map?;
            } else if (decoded[song.id] is Map) {
              rawSong = decoded[song.id] as Map;
            } else if (decoded['data'] is List && (decoded['data'] as List).isNotEmpty) {
              rawSong = (decoded['data'] as List).first as Map?;
            }
            if (rawSong != null) {
              final data = Map<String, dynamic>.from(rawSong);
              final more = data['more_info'] is Map ? Map<String, dynamic>.from(data['more_info'] as Map) : <String, dynamic>{};
              final encrypted = _firstString(more, ['encrypted_media_url', 'encrypted_media_path', 'encrypted_url']).isNotEmpty
                  ? _firstString(more, ['encrypted_media_url', 'encrypted_media_path', 'encrypted_url'])
                  : _firstString(data, ['encrypted_media_url', 'encrypted_media_path', 'encrypted_url']);
              final is320 = _string(more, '320kbps').toLowerCase() == 'true';
              if (encrypted.isNotEmpty) {
                final decrypted = _decryptMediaUrl(encrypted);
                if (_isHttpUrl(decrypted)) {
                  return _selectQuality(decrypted, quality, is320);
                }
              }
              final fallbackUrl = _firstHttpUrl([_string(more, 'media_preview_url'), _string(more, 'vlink'), _string(data, 'media_preview_url')]);
              if (fallbackUrl != null) return fallbackUrl;
            }
          }
        }
      }
      if (_isHttpUrl(song.mediaUrl) && !song.mediaUrl.contains('/catalog/music/stream/')) {
        final safeUrl = song.mediaUrl.startsWith('http://')
            ? song.mediaUrl.replaceFirst('http://', 'https://')
            : song.mediaUrl;
        final has320 = safeUrl.contains('_320');
        return _selectQuality(safeUrl, quality, has320);
      }
      return null;

    } catch (error, stack) {
      _debugLog.error('JIOSAAVN PLAY resolve failed: $error');
      _debugLog.error(_oneLineStack(stack));
    }

    // Native clients can recover through the backend if the direct provider
    // details request fails or returns an incomplete payload.
    try {
      if (song.id.trim().isNotEmpty) {
        final response = await AuthService().get(
          '/catalog/music/stream/${Uri.encodeComponent(song.id)}/',
          authenticated: false,
        );
        var url = _string(response, 'media_url');
        if (url.startsWith('http://')) {
          url = url.replaceFirst('http://', 'https://');
        }
        if (_isHttpUrl(url)) return url;
      }
    } catch (error) {
      _debugLog.warning('Backend stream fallback failed: $error');
    }

    if (_isHttpUrl(song.mediaUrl) && !song.mediaUrl.contains('/catalog/music/stream/')) {
      final safeUrl = song.mediaUrl.startsWith('http://')
          ? song.mediaUrl.replaceFirst('http://', 'https://')
          : song.mediaUrl;
      return _selectQuality(
        safeUrl,
        quality,
        safeUrl.contains('_320'),
      );
    }
    return null;
  }

  Future<String?> fetchLyricsId(String songId) async {
    if (songId.trim().isEmpty) return null;
    try {
      final uri = Uri.parse(_baseUrl).replace(queryParameters: {
        '__call': 'song.getDetails', 'pids': songId, '_format': 'json', '_marker': '0',
        'cc': 'in', 'ctx': 'web6dot0', 'api_version': '4',
      });
      final response = await http.get(uri, headers: const {'User-Agent': 'Mozilla/5.0'});
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      final songs = decoded is Map ? decoded['songs'] : null;
      final raw = songs is List && songs.isNotEmpty ? songs.first : null;
      if (raw is! Map) return null;
      final more = raw['more_info'] is Map ? Map<String, dynamic>.from(raw['more_info'] as Map) : <String, dynamic>{};
      return _firstString(Map<String, dynamic>.from(raw), ['lyrics_id']).isNotEmpty
          ? _firstString(Map<String, dynamic>.from(raw), ['lyrics_id'])
          : _string(more, 'lyrics_id');
    } catch (_) {
      return null;
    }
  }

  String _decryptMediaUrl(String encryptedUrl) {
    try {
      final encryptedBytes = base64.decode(encryptedUrl);
      final des = DES(key: _jioSaavnDesKey.codeUnits, mode: DESMode.ECB);
      final decryptedBytes = des.decrypt(encryptedBytes);
      var url = utf8.decode(decryptedBytes).trim().replaceAll(RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]'), '');
      if (url.startsWith('http://')) {
        url = url.replaceFirst('http://', 'https://');
      }
      return url;
    } catch (_) {
      return '';
    }
  }

  String _selectQuality(String url, String quality, bool has320) {
    if (quality == 'auto') return has320 ? _replaceQuality(url, '320') : url;
    if (quality == '320' && !has320) return url;
    return _replaceQuality(url, quality);
  }

  String _replaceQuality(String url, String quality) => url.replaceFirst(RegExp(r'_(96|160|320)(?=[._])'), '_$quality');

  String _highResArtwork(String url) {
    if (url.isEmpty) return url;
    return url.replaceFirst(
      RegExp(r'(?<!\d)(50|150|320|500)x(?:50|150|320|500)(?=\.)'),
      '500x500',
    );
  }

  String _string(Map<String, dynamic> map, String key) =>
      TrackNormalizer.unescapeHtml(map[key]?.toString().trim() ?? '');

  String _firstString(Map<String, dynamic> map, Iterable<String> keys) {
    for (final key in keys) {
      final value = _string(map, key);
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  String? _firstHttpUrl(Iterable<String> values) {
    for (final value in values) {
      if (_isHttpUrl(value)) {
        return value.startsWith('http://')
            ? value.replaceFirst('http://', 'https://')
            : value;
      }
    }
    return null;
  }

  bool _isHttpUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
  }

  String _oneLineStack(StackTrace stack) => stack.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}
