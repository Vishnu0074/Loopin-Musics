# Flutter Web player deployment

The Django landing page remains at the existing website root. Its `/player/` route redirects to the Flutter Web app only after `LOOPIN_WEB_PLAYER_URL` is configured; until then, the existing Django player remains available as a safe fallback.

## Build the Flutter Web bundle

From the repository root:

```sh
flutter pub get
flutter build web --release \
  --dart-define=LOOPIN_API_URL=https://loopin-api-xuaf.onrender.com/api \
  --dart-define=LOOPIN_WS_URL=wss://loopin-api-xuaf.onrender.com/ws/player/
```

Upload the contents of `build/web/` to an HTTPS static host and attach the dedicated app subdomain. Keep the site at the root of that subdomain (the Flutter build uses the default base href).

## Connect the landing page

In the Render service that serves the Django landing page/API, set:

- `LOOPIN_WEB_PLAYER_URL=https://<your-app-subdomain>`

The setting makes Django's `/player/` route redirect to Flutter Web and automatically adds that origin to `CORS_ALLOWED_ORIGINS`. Redeploy the Django service after setting the environment variable.

The current Render `loopin-api` service is configured to deploy from the `Vishnu0074/loopin` repository with root directory `backend`. The standalone `Vishnu0074/Backend_Loopin` repository is not the source configured for that Render service.

## Web-specific behavior

- Flutter Web catalog searches and lyrics requests go through the Django API instead of calling those JSON APIs directly from the browser.
- Web playback prefers Django's authenticated audio-stream proxy to avoid browser cross-origin restrictions.
- Native notification/background audio initialization is skipped on web; mobile and desktop paths remain unchanged.
- The landing-page Player links open `/player/` in a new tab. The Django route performs the redirect only when configured.

## Validation checklist

1. Require a green `Flutter Web Build` workflow before merging.
2. Confirm the deployed static site serves `index.html` and `flutter_bootstrap.js` over HTTPS.
3. Set `LOOPIN_WEB_PLAYER_URL` to the final app subdomain and verify `/player/` redirects.
4. In a browser, test login/register, catalog search, playback/seek, likes, lyrics, playlists and the WebSocket connection with the mobile app.
