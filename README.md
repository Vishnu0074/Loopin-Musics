# Loopin V2

A Flutter music player built on the original Loopin application experience and adapted to use Monochrome's open-source Tracks Streamer API.

## Music provider

- Search metadata: Monochrome Tracks Streamer
- Playback URL resolution: Tracks Streamer `/track/{trackId}`
- Smart recommendations: local listening signals, favourites, skips, language, genre, tempo and artist affinity
- Lyrics: LRCLIB with Lyrics.ovh fallback
- Library, liked songs, playlists and listening history: local encrypted storage on native platforms and browser storage on web

Configure an alternate Tracks Streamer host with:

```bash
flutter run --dart-define=MONOCHROME_TRACKS_API=https://tracks.monochrome.st
```

To enable optional account endpoints, supply your own compatible Loopin backend at launch:

```bash
flutter run \
  --dart-define=LOOPIN_API_URL=https://your-backend.example/api \
  --dart-define=LOOPIN_WS_URL=wss://your-backend.example/ws/player/
```

## Project notes

The original Loopin Django backend and IDE extension are intentionally not included in this repository. Authentication-backed features and cross-device Listen Together require a separately deployed backend; local playback, discovery and personal-library features do not.

This project reuses the Loopin Flutter application source. Monochrome's upstream project is available at https://github.com/Vishnu0074/monochrome. Retain the upstream project's license and notices when redistributing any of its code.
