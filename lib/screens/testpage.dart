import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import '../widgets/loopin_snackbar.dart';
class Song {
  final String title;
  final String artist;
  final String mediaUrl;

  Song({required this.title, required this.artist, required this.mediaUrl});

  factory Song.fromJson(Map<String, dynamic> json) {
    return Song(
      title: json['name'] ?? 'Unknown Title',
      artist: json['primaryArtists'] ?? 'Unknown Artist',
      mediaUrl: json['downloadUrl']?[4]?['link'] ?? '', // 320kbps
    );
  }
}

class SongSearchScreen extends StatefulWidget {
  const SongSearchScreen({super.key});

  @override
  State<SongSearchScreen> createState() => _SongSearchScreenState();
}

class _SongSearchScreenState extends State<SongSearchScreen> {
  final TextEditingController _controller = TextEditingController();
  List<Song> _songs = [];
  bool _isLoading = false;
  final AudioPlayer _player = AudioPlayer();

  Future<void> _searchSongs(String query) async {
    setState(() {
      _isLoading = true;
      _songs = [];
    });

    final response = await http.get(
      Uri.parse('https://saavn.dev/api/search/songs?query=$query'),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final List results = data['data']['results'];

      final List<Song> songs = [];

      for (var song in results) {
        // Get full song details to extract download link
        final id = song['id'];
        final detailsResp = await http.get(
          Uri.parse('https://saavn.dev/api/songs/$id'),
        );
        if (detailsResp.statusCode == 200) {
          final songJson = jsonDecode(detailsResp.body)['data'][0];
          songs.add(Song.fromJson(songJson));
        }
      }

      if (!mounted) return;
      setState(() {
        _songs = songs;
        _isLoading = false;
      });
    } else {
      if (!mounted) return;
      setState(() => _isLoading = false);
      LoopinSnackBar.show(context, "Failed to fetch songs");
    }
  }

  void _play(String url) async {
    try {
      await _player.setUrl(url);
      unawaited(_player.play());
    } catch (e) {
      if (!mounted) return;
      LoopinSnackBar.show(context, "Error playing song");
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Loopin Music 🎧')),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            TextField(
              controller: _controller,
              decoration: InputDecoration(
                hintText: "Search songs...",
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () => _searchSongs(_controller.text),
                ),
              ),
            ),
            const SizedBox(height: 10),
            if (_isLoading) const LinearProgressIndicator(),
            Expanded(
              child: ListView.builder(
                itemCount: _songs.length,
                itemBuilder: (context, index) {
                  final song = _songs[index];
                  return ListTile(
                    leading: const Icon(Icons.music_note),
                    title: Text(song.title),
                    subtitle: Text(song.artist),
                    trailing: IconButton(
                      icon: const Icon(Icons.play_arrow),
                      onPressed: () => _play(song.mediaUrl),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
