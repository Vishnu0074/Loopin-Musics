import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../lib/models/song.dart';
import '../lib/services/monochrome_api.dart';

void main() {
  group('MonochromeApi', () {
    test('normalizes Tracks Streamer search results and resolves direct streams', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/search/tracks');
        expect(request.url.queryParameters['q'], 'Malare');
        return http.Response(
          jsonEncode({
            'tracks': [
              {
                'trackId': 'track-42',
                'title': 'Malare',
                'artistNames': ['Vijay Yesudas'],
                'albumTitle': 'Premam',
                'artwork': 'https://cdn.example.test/malare.jpg',
                'duration': 240000,
                'isrc': 'INABC2400001',
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final api = MonochromeApi(client: client);
      addTearDown(api.dispose);

      final songs = await api.search('Malare', pages: 1, limit: 1);

      expect(songs, hasLength(1));
      expect(songs.single.id, 'track-42');
      expect(songs.single.artist, 'Vijay Yesudas');
      expect(songs.single.album, 'Premam');
      expect(songs.single.durationSeconds, 240);
      expect(
        await api.resolveStream(songs.single),
        'https://tracks.monochrome.st/track/track-42',
      );
    });

    test('resolves imported metadata to a matching Tracks Streamer track', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'tracks': [
              {
                'trackId': 'resolved-9',
                'title': 'Aaradhike',
                'artistNames': ['Sooraj Santhosh'],
                'duration': 218,
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final api = MonochromeApi(client: client);
      addTearDown(api.dispose);

      const imported = Song(
        id: 'external-1',
        title: 'Aaradhike',
        artist: 'Sooraj Santhosh',
        imageUrl: '',
        mediaUrl: '',
        durationSeconds: 218,
      );

      expect(
        await api.resolveStream(imported),
        'https://tracks.monochrome.st/track/resolved-9',
      );
    });
  });
}
