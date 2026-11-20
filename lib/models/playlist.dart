import 'song.dart';
class PlaylistSong {
  final int id; final String songId,title,artist; final String? album,imageUrl; final int position;
  const PlaylistSong({required this.id,required this.songId,required this.title,required this.artist,this.album,this.imageUrl,required this.position});
  Song toSong()=>Song(id:songId,title:title,artist:artist,album:album,imageUrl:imageUrl??'',mediaUrl:'');
  factory PlaylistSong.fromJson(Map<String,dynamic> j)=>PlaylistSong(id:int.tryParse(j['id'].toString())??0,songId:j['song_id']?.toString()??'',title:j['title']?.toString()??'',artist:j['artist']?.toString()??'',album:j['album']?.toString(),imageUrl:j['image_url']?.toString(),position:int.tryParse(j['position'].toString())??0);
}
class Playlist {
  final int id; final String name; final String? imageUrl, owner; final int songCount; final bool isPublic;
  const Playlist({required this.id,required this.name,this.imageUrl,this.owner,required this.songCount,this.isPublic=false});
  factory Playlist.fromJson(Map<String,dynamic> j)=>Playlist(id:int.tryParse(j['id'].toString())??0,name:j['name']?.toString()??'Playlist',imageUrl:j['image_url']?.toString(),songCount:int.tryParse(j['song_count'].toString())??0,owner:j['owner']?.toString(),isPublic:j['is_public']==true);
}
