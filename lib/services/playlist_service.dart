import 'dart:convert';

import '../models/song.dart';
import '../models/playlist.dart';
import 'app_storage.dart';
import 'recommendation_service.dart';
import 'stats_service.dart';

/// Local-first playlist and library storage. Playlists, likes and history work
/// without a Loopin Django server; public visibility is local to this device.
class PlaylistService {
  final AppStorage _storage = AppStorage();
  static const _key = 'loopin_v2_playlists';

  Future<List<Map<String, dynamic>>> _rows() async {
    final raw = await _storage.read(key: _key);
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

  Future<void> _save(List<Map<String, dynamic>> rows) =>
      _storage.write(key: _key, value: jsonEncode(rows));

  Playlist _model(Map<String, dynamic> row) {
    final songs = row['songs'] is List ? row['songs'] as List : const [];
    return Playlist(
      id: (row['id'] as num?)?.toInt() ?? 0,
      name: row['name']?.toString() ?? 'Playlist',
      imageUrl: row['image_url']?.toString(),
      songCount: songs.length,
      owner: 'You',
      isPublic: row['is_public'] == true,
    );
  }

  Future<List<Playlist>> list() async => (await _rows()).map(_model).toList();

  Future<List<Playlist>> publicList() async =>
      (await _rows()).where((row) => row['is_public'] == true).map(_model).toList();

  Future<Playlist> create(String name, {bool isPublic = false}) async {
    final rows = await _rows();
    final id = DateTime.now().microsecondsSinceEpoch;
    final row = <String, dynamic>{
      'id': id,
      'name': name.trim().isEmpty ? 'New Playlist' : name.trim(),
      'is_public': isPublic,
      'songs': <Map<String, dynamic>>[],
      'created_at': DateTime.now().toIso8601String(),
    };
    rows.insert(0, row);
    await _save(rows);
    return _model(row);
  }

  Future<Map<String, dynamic>> detail(int id) async {
    final rows = await _rows();
    final row = rows.firstWhere((item) => (item['id'] as num?)?.toInt() == id,
        orElse: () => throw StateError('Playlist not found.'));
    final rawSongs = (row['songs'] as List? ?? const []);
    return {
      ...row,
      'can_edit': true,
      'songs': rawSongs.asMap().entries.map((entry) {
        final data = Map<String, dynamic>.from(entry.value as Map);
        data['song_id'] = data['id'];
        data['id'] = entry.key + 1;
        data['position'] = entry.key;
        return data;
      }).toList(),
    };
  }

  Future<void> addSong(int id, Song song) async {
    final rows = await _rows();
    final row = rows.firstWhere((item) => (item['id'] as num?)?.toInt() == id,
        orElse: () => throw StateError('Playlist not found.'));
    final songs = (row['songs'] as List? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map)).toList();
    if (songs.any((item) => item['id']?.toString() == song.id)) return;
    songs.add({...song.toJson(), 'position': songs.length});
    row['songs'] = songs;
    await _save(rows);
  }

  Future<void> removeSong(int id, String songId) async {
    final rows = await _rows();
    final row = rows.firstWhere((item) => (item['id'] as num?)?.toInt() == id,
        orElse: () => throw StateError('Playlist not found.'));
    final songs = (row['songs'] as List? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .where((item) => item['id']?.toString() != songId)
        .toList();
    for (var i = 0; i < songs.length; i++) {
      songs[i]['position'] = i;
    }
    row['songs'] = songs;
    await _save(rows);
  }

  Future<void> reorder(int id, List<String> ids) async {
    final rows = await _rows();
    final row = rows.firstWhere((item) => (item['id'] as num?)?.toInt() == id,
        orElse: () => throw StateError('Playlist not found.'));
    final current = (row['songs'] as List? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map)).toList();
    final byId = {for (final item in current) item['id']?.toString() ?? '': item};
    final reordered = <Map<String, dynamic>>[];
    for (final songId in ids) {
      final item = byId.remove(songId);
      if (item != null) reordered.add(item);
    }
    reordered.addAll(byId.values);
    for (var i = 0; i < reordered.length; i++) {
      reordered[i]['position'] = i;
    }
    row['songs'] = reordered;
    await _save(rows);
  }

  Future<Map<String, dynamic>> sources() async {
    final liked = await RecommendationService().loadLikedSongs();
    final recent = await RecommendationService().loadHistory(limit: 100);
    Map<String, dynamic> row(Song song) => {
      'song_id': song.id,
      'title': song.title,
      'artist': song.artist,
      'album': song.album ?? '',
      'image_url': song.imageUrl,
    };
    return {
      'liked': liked.map(row).toList(),
      'recent': recent.map(row).toList(),
      'search': <Map<String, dynamic>>[],
      'sources': ['Monochrome Tracks Streamer'],
      'import_supported': false,
    };
  }

  Future<List<Song>> likedSongs() => RecommendationService().loadLikedSongs();

  Future<Map<String, dynamic>> historyPage({int page = 1, int pageSize = 20}) async {
    final songs = await RecommendationService().loadHistory(limit: 1000);
    final start = ((page - 1) * pageSize).clamp(0, songs.length).toInt();
    final items = songs.skip(start).take(pageSize).map((song) => {
      'song_id': song.id,
      'title': song.title,
      'artist': song.artist,
      'album': song.album ?? '',
      'image_url': song.imageUrl,
      'played_at': null,
    }).toList();
    return {
      'count': songs.length,
      'items': items,
      'has_next': start + pageSize < songs.length,
      'results': items,
      'next': start + pageSize < songs.length ? page + 1 : null,
      'previous': page > 1 ? page - 1 : null,
    };
  }

  Future<bool> toggleLike(Song song) => RecommendationService().toggleLike(song);

  Future<Map<String, dynamic>> stats() => StatsService().getCombinedStats();
}
