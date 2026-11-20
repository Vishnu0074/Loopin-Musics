class Song {
  final String id;
  final String title;
  final String artist;
  final String imageUrl;
  final String mediaUrl;
  final String? album;
  final String? isrc;
  final String? language;
  final int? durationSeconds;
  final double? tempo;
  final String? genre;
  final String? lyricsId;

  const Song({
    required this.id,
    required this.title,
    required this.artist,
    required this.imageUrl,
    required this.mediaUrl,
    this.album,
    this.isrc,
    this.language,
    this.durationSeconds,
    this.tempo,
    this.genre,
    this.lyricsId,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'artist': artist,
    'image_url': imageUrl,
    'media_url': mediaUrl,
    if (album != null) 'album': album,
    if (isrc != null) 'isrc': isrc,
    if (language != null) 'language': language,
    if (durationSeconds != null) 'duration_seconds': durationSeconds,
    if (tempo != null) 'tempo': tempo,
    if (genre != null) 'genre': genre,
    if (lyricsId != null) 'lyrics_id': lyricsId,
  };

  factory Song.fromJson(Map<String, dynamic> json) {
    final rawMedia = json['media_url']?.toString() ?? '';
    return Song(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Unknown Title',
      artist: json['artist']?.toString() ?? 'Unknown Artist',
      imageUrl: json['image_url']?.toString() ?? '',
      mediaUrl: rawMedia.contains('/catalog/music/stream/') ? '' : rawMedia,
      album: json['album']?.toString(),
      isrc: json['isrc']?.toString(),
      language: json['language']?.toString(),
      durationSeconds: json['duration_seconds'] is num
          ? (json['duration_seconds'] as num).toInt()
          : int.tryParse(json['duration_seconds']?.toString() ?? ''),
      tempo: json['tempo'] is num
          ? (json['tempo'] as num).toDouble()
          : double.tryParse(json['tempo']?.toString() ?? ''),
      genre: json['genre']?.toString(),
      lyricsId: json['lyrics_id']?.toString(),
    );
  }
}
