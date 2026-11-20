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
      mediaUrl: json['downloadUrl']?[4]?['link'] ?? '',
    );
  }
}

class FilteredSongScreen extends StatefulWidget {
  const FilteredSongScreen({super.key});

  @override
  State<FilteredSongScreen> createState() => _FilteredSongScreenState();
}

class _FilteredSongScreenState extends State<FilteredSongScreen> {
  final AudioPlayer _player = AudioPlayer();
  bool _isLoading = false;
  List<Song> _songs = [];
  String _selectedFilter = '';
  final List<String> _filters = ['Romantic', 'Pop', 'Sad', 'Retro', 'Lofi', 'Trending'];

  Future<void> _fetchSongs(String category) async {
    setState(() {
      _isLoading = true;
      _songs = [];
      _selectedFilter = category;
    });

    final response = await http.get(
      Uri.parse('https://saavn.dev/api/search/songs?query=$category'),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final List results = data['data']['results'];

      final List<Song> songs = [];

      for (var song in results.take(10)) { // Limit to 10 for speed
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
    } catch (_) {
      if (!mounted) return;
      LoopinSnackBar.show(context, "Error playing song");
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Loopin Filter 🎵')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            children: _filters.map((filter) {
              return FilterChip(
                label: Text(filter),
                selected: _selectedFilter == filter,
                onSelected: (bool selected) {
                  if (selected) {
                    _fetchSongs(filter);
                  }
                },
              );
            }).toList(),
          ),
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
    );
  }
}
