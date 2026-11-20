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
flutter run \
  --dart-define=MONOCHROME_TRACKS_API=https://tracks.monochrome.st
```

If you have an authorized alternate Tracks Streamer instance, set its URL as the primary host and optionally provide comma-separated fallbacks:

```bash
flutter run \
  --dart-define=MONOCHROME_TRACKS_API=https://your-authorized-host.example \
  --dart-define=MONOCHROME_TRACKS_APIS=https://fallback-one.example,https://fallback-two.example
```

Every configured host must implement the Tracks Streamer `/search/tracks` and `/track/{trackId}` routes. **Important:** Monochrome documents that its hosted music API only accepts official Monochrome instances. The default host may therefore reject Loopin V2; use a host that has explicitly authorized this app or your own compatible service.

To enable optional account endpoints, supply your own compatible Loopin backend at launch:

```bash
flutter run \
  --dart-define=LOOPIN_API_URL=https://your-backend.example/api \
  --dart-define=LOOPIN_WS_URL=wss://your-backend.example/ws/player/
```

## Build an Android APK with GitHub Actions

APK builds are manual-only; pushes and pull requests do not trigger a build.

1. Open the repository's **Actions** tab.
2. Select **Build Android APK**.
3. Select **Run workflow** on the `main` branch.
4. Optionally enter an authorized Tracks Streamer primary URL and comma-separated fallback URLs.
5. Download `loopin-v2-android-release-apk` from the completed run's Artifacts section.

The workflow provisions Java 17, Flutter 3.44.0, Android SDK 36, Build Tools 36.0.0 and NDK 27.0.12077973, restores Gradle dependencies, runs Flutter tests and builds the release APK.

The current Android release build uses the Gradle debug signing key so the APK can be installed for testing. Configure a private release keystore and GitHub Actions secrets before publishing to Google Play.

## Platform setup

The migrated source contains Android, web and Windows runners. The original repository did not include an iOS runner; generate it before building for iPhone or iPad:

```bash
flutter create --platforms=ios .
flutter pub get
```

## Project notes

The original Loopin Django backend and IDE extension are intentionally not included in this repository. Authentication, admin tools, globally shared public playlists and cross-device Listen Together require a separately deployed backend. In standalone mode, playlists marked public are only visible in the local Public playlists section; local playback, discovery, likes, history and recommendations work without a backend.

This project reuses the Loopin Flutter application source. Monochrome's upstream project is available at https://github.com/Vishnu0074/monochrome. Retain the upstream project's license and notices when redistributing any of its code.
