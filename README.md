# Loopin

Loopin is a dark-themed Flutter music player for mobile and desktop.

## Windows desktop build

Install Flutter stable and Visual Studio 2022 with the **Desktop development with C++** workload, then run in PowerShell from the repository root:

```powershell
flutter create --platforms=windows .
flutter pub get
flutter build windows --release
```

The project originally started as a mobile-first Flutter app, so Flutter's standard Windows runner is generated before building. The Windows CI workflow runs these commands and uploads the release output as a GitHub Actions artifact.

Windows playback uses `just_audio_windows`. Android notification and Android audio-session setup remain platform-gated, so they do not block desktop initialization.

## Web and macOS Now Playing integration

On supported browsers, Loopin publishes the active track title, artist, album, and
cover artwork through the browser Media Session API. This allows macOS to show
track details and artwork in its system Now Playing panel when playback is
running in the browser. The same integration exposes play/pause, previous/next,
and seek actions where the browser supports them. Native platforms continue to
use their existing audio background integrations.

## High-resolution artwork

JioSaavn search results normalize known thumbnail URLs to the 500×500 cover variant when the provider exposes size variants. UI components should use the normalized `Song.imageUrl` and provide a fallback for unavailable artwork.
