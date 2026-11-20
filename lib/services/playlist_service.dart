import '../models/song.dart';
import '../models/playlist.dart';
import 'auth_service.dart';
import 'stats_service.dart';

class PlaylistService {
  final AuthService _api=AuthService();
  Future<List<Playlist>> list() async { final d=await _api.get('/playlists/'); final own=(d['playlists'] as List? ?? const []).whereType<Map>().map((x)=>Playlist.fromJson(Map<String,dynamic>.from(x))); final pub=(d['public_playlists'] as List? ?? const []).whereType<Map>().map((x)=>Playlist.fromJson(Map<String,dynamic>.from(x))); return [...own,...pub]; }
  Future<List<Playlist>> publicList() async { final d=await _api.get('/playlists/'); return (d['public_playlists'] as List? ?? const []).whereType<Map>().map((x)=>Playlist.fromJson(Map<String,dynamic>.from(x))).toList(); }
  Future<Playlist> create(String name, {bool isPublic=false}) async { final d=await _api.post('/playlists/',{'name':name,'is_public':isPublic}); return Playlist.fromJson(d); }
  Future<Map<String,dynamic>> detail(int id) => _api.get('/playlists/$id/');
  Future<void> addSong(int id,Song s) async { await _api.post('/playlists/$id/songs/',{'song_id':s.id,'title':s.title,'artist':s.artist,'album':s.album??'','image_url':s.imageUrl}); }
  Future<void> removeSong(int id,String songId) async { await _api.delete('/playlists/$id/songs/?song_id=${Uri.encodeComponent(songId)}'); }
  Future<void> reorder(int id,List<String> ids) async { await _api.patch('/playlists/$id/reorder/',{'song_ids':ids}); }
  Future<Map<String,dynamic>> sources() => _api.get('/playlists/sources/');
  Future<List<Song>> likedSongs() async {
    final data=await _api.get('/listening/likes/');
    return (data['likes'] as List? ?? const []).whereType<Map>().map((row)=>Song(
      id:row['song_id']?.toString()??'',
      title:row['title']?.toString()??'',
      artist:row['artist']?.toString()??'Unknown Artist',
      album:row['album']?.toString(),
      imageUrl:row['image_url']?.toString()??'',
      mediaUrl:'',
    )).where((song)=>song.id.isNotEmpty).toList();
  }
  Future<Map<String,dynamic>> historyPage({int page=1,int pageSize=20}) =>
      _api.get('/listening/history/?page=$page&page_size=$pageSize');
  Future<bool> toggleLike(Song song) async {
    final result=await _api.post('/listening/likes/',{
      'song_id':song.id,'title':song.title,'artist':song.artist,
      'album':song.album??'','image_url':song.imageUrl,
    });
    return result['liked']==true;
  }
  Future<Map<String,dynamic>> stats() => StatsService().getCombinedStats();
}
