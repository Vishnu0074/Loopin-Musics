import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'auth_service.dart';
import 'app_storage.dart';
import '../models/song.dart';

typedef RealtimeCommandHandler = Future<void> Function(String command, Map<String, dynamic> payload);
typedef RealtimeStateHandler = Future<void> Function(Map<String, dynamic> state);
typedef RealtimeLyricsHandler = Future<void> Function(String? trackId, String? lyrics);
typedef RealtimeQueueHandler = Future<void> Function(List<Map<String, dynamic>> queue);
typedef RealtimePlaybackEventHandler = Future<void> Function(Map<String, dynamic> event);
typedef RealtimeCommandResultHandler = void Function(Map<String, dynamic> result);
typedef RealtimeOwnershipHandler = void Function(bool isOwner);
typedef RealtimeConnectionHandler = void Function();

class RealtimePlayerService {
  static final RealtimePlayerService _instance = RealtimePlayerService._();
  factory RealtimePlayerService() => _instance;
  RealtimePlayerService._();

  static const _socketBase = String.fromEnvironment(
    'LOOPIN_WS_URL',
    defaultValue: 'wss://loopin-api-xuaf.onrender.com/ws/player/',
  );

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Future<void>? _connecting;
  Future<void> _incomingMessageJob = Future<void>.value();
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;
  bool _disposed = false;
  bool _standaloneMode = false;
  Future<void>? _modeLoadJob;
  bool _modeInitialized = false;
  static const String _standaloneStorageKey = 'loopin_standalone_mode';
  final AppStorage _storage = AppStorage();
  bool get standaloneMode => _standaloneMode;
  final String _clientId = '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-${Random().nextInt(1 << 31).toRadixString(36)}';
  RealtimeCommandHandler? _onCommand;
  RealtimeStateHandler? _onState;
  RealtimeLyricsHandler? _onLyrics;
  RealtimeQueueHandler? _onQueue;
  RealtimePlaybackEventHandler? _onPlaybackEvent;
  RealtimeCommandResultHandler? _onCommandResult;
  RealtimeOwnershipHandler? _onOwnershipChanged;
  RealtimeConnectionHandler? _onConnected;

  bool _socketReady = false;
  bool get connected => _socketReady;
  bool _hasOwnerStatus = false;
  bool _isPlaybackOwner = true;
  bool get isPlaybackOwner => _standaloneMode || !_socketReady || !_hasOwnerStatus || _isPlaybackOwner;

  Future<void> initializeMode() => _ensureModeLoaded();

  Future<void> _ensureModeLoaded() async {
    if (_modeInitialized) return;
    if (_modeLoadJob != null) return _modeLoadJob;
    _modeLoadJob = () async {
      _standaloneMode = (await _storage.read(key: _standaloneStorageKey)) == 'true';
      _modeInitialized = true;
    }();
    try {
      await _modeLoadJob;
    } finally {
      _modeLoadJob = null;
    }
  }

  Future<void> setStandaloneMode(bool enabled) async {
    await _ensureModeLoaded();
    if (_standaloneMode == enabled) return;
    _standaloneMode = enabled;
    await _storage.write(key: _standaloneStorageKey, value: enabled ? 'true' : 'false');
    if (enabled) {
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      _heartbeatTimer?.cancel();
      _heartbeatTimer = null;
      final subscription = _subscription;
      _subscription = null;
      await subscription?.cancel();
      final channel = _channel;
      _channel = null;
      _socketReady = false;
      _hasOwnerStatus = false;
      _isPlaybackOwner = true;
      try { await channel?.sink.close(); } catch (_) {}
      _onOwnershipChanged?.call(true);
    } else {
      final pendingConnection = _connecting;
      if (pendingConnection != null) {
        try { await pendingConnection; } catch (_) {}
      }
      await connect();
    }
  }

  Future<void> connect({
    RealtimeCommandHandler? onCommand,
    RealtimeStateHandler? onState,
    RealtimeLyricsHandler? onLyrics,
    RealtimeQueueHandler? onQueue,
    RealtimePlaybackEventHandler? onPlaybackEvent,
    RealtimeCommandResultHandler? onCommandResult,
    RealtimeOwnershipHandler? onOwnershipChanged,
    RealtimeConnectionHandler? onConnected,
  }) async {
    _onCommand = onCommand ?? _onCommand;
    _onState = onState ?? _onState;
    _onLyrics = onLyrics ?? _onLyrics;
    _onQueue = onQueue ?? _onQueue;
    _onPlaybackEvent = onPlaybackEvent ?? _onPlaybackEvent;
    _onCommandResult = onCommandResult ?? _onCommandResult;
    _onOwnershipChanged = onOwnershipChanged ?? _onOwnershipChanged;
    _onConnected = onConnected ?? _onConnected;
    await _ensureModeLoaded();
    if (_standaloneMode || _disposed) return;
    if (_socketReady || _connecting != null) {
      return _connecting ?? Future.value();
    }
    _connecting = _connectInternal();
    try {
      await _connecting;
    } finally {
      _connecting = null;
    }
  }

  Future<void> _connectInternal() async {
    await _ensureModeLoaded();
    if (_disposed || _standaloneMode) return;
    try {
      // Refresh before establishing a background/reconnect socket so a long-lived
      // playback session does not reconnect with an expired access token.
      final auth = AuthService();
      final tokenBeforeRefresh = await auth.accessToken();
      if (tokenBeforeRefresh == null || tokenBeforeRefresh.isEmpty) {
        // Guests and signed-out sessions have no realtime work to perform.
        // Do not run a permanent reconnect loop while the app is on splash/home.
        return;
      }
      await auth.refreshAccessToken();
      final token = await auth.accessToken();
      if (_disposed || _standaloneMode || token == null || token.isEmpty) return;
      final uri = Uri.parse(_socketBase).replace(queryParameters: {'token': token, 'client_id': _clientId, 'role': 'player'});
      final channel = WebSocketChannel.connect(uri);
      _channel = channel;
      await channel.ready;
      if (_disposed || _standaloneMode || !identical(_channel, channel)) {
        await channel.sink.close();
        return;
      }
      _socketReady = true;
      _subscription = channel.stream.listen(
        (raw) async {
          final previousMessage = _incomingMessageJob;
          final messageDone = Completer<void>();
          _incomingMessageJob = messageDone.future;
          try {
            await previousMessage;
            if (!identical(_channel, channel)) return;
            try {
            final decoded = raw is String ? jsonDecode(raw) : raw;
            if (decoded is! Map) return;
            final data = Map<String, dynamic>.from(decoded);
            switch (data['type']) {
              case 'playback_owner': {
                final wasOwner = _isPlaybackOwner;
                _hasOwnerStatus = true;
                _isPlaybackOwner = data['owner_id'] == _clientId || data['is_owner'] == true;
                if (wasOwner != _isPlaybackOwner) {
                  _onOwnershipChanged?.call(_isPlaybackOwner);
                }
                break;
              }
              case 'player_command':
                final command = data['command']?.toString();
                final requestId = data['request_id']?.toString();
                if (command != null && _onCommand != null) {
                  try {
                    await _onCommand!(command, data);
                    if (requestId != null) {
                      _sendCommandResult(requestId, true, replyChannel: data['reply_channel']?.toString());
                    }
                  } catch (error) {
                    if (requestId != null) {
                      _sendCommandResult(requestId, false, error: error.toString(), replyChannel: data['reply_channel']?.toString());
                    }
                  }
                }
                break;
              case 'command_result':
                _onCommandResult?.call(data);
                break;
              case 'error':
                _onCommandResult?.call({
                  'success': false,
                  'request_id': data['request_id'],
                  'error': data['message'] ?? data['error'] ?? 'Realtime command failed.',
                });
                break;
              case 'player_state':
                if (_onState != null) {
                  await _onState!({
                    'track': data['track'],
                    'position_ms': _asInt(data['position_ms']),
                    'duration_ms': _asInt(data['duration_ms']),
                    'playing': data['playing'] == true,
                    'queue': data['queue'] is List ? data['queue'] : const [],
                    'lyrics': data['lyrics'],
                    'revision': _asInt(data['revision']),
                  });
                }
                break;
              case 'playback_event':
                if (_onPlaybackEvent != null) {
                  await _onPlaybackEvent!(data);
                }
                break;
              case 'lyrics':
                if (_onLyrics != null) {
                  await _onLyrics!(data['track_id']?.toString(), data['lyrics']?.toString());
                }
                break;
              case 'queue':
                if (_onQueue != null) {
                  final queue = data['queue'] is List
                      ? (data['queue'] as List)
                          .whereType<Map>()
                          .map((item) => Map<String, dynamic>.from(item))
                          .toList()
                      : <Map<String, dynamic>>[];
                  await _onQueue!(queue);
                }
                break;
            }
            } catch (_) {}
          } finally {
            messageDone.complete();
          }
        },
        onDone: () {
          if (identical(_channel, channel)) _reset();
        },
        onError: (_, __) {
          if (identical(_channel, channel)) _reset();
        },
        cancelOnError: false,
      );
      _onConnected?.call();
      channel.sink.add(jsonEncode({'action': 'subscribe'}));
      _heartbeatTimer ??= Timer.periodic(const Duration(seconds: 20), (_) {
        final active = _channel;
        if (_disposed || active == null) return;
        try {
          // subscribe is also our lightweight application-level heartbeat and
          // asks Django for the authoritative player state after idle periods.
          active.sink.add(jsonEncode({'action': 'subscribe'}));
        } catch (_) {
          _reset();
        }
      });
    } catch (_) {
      _reset();
    }
  }

  void _scheduleReconnect() {
    if (_disposed || _standaloneMode || _reconnectTimer != null) return;
    _reconnectTimer = Timer(const Duration(seconds: 2), () async {
      _reconnectTimer = null;
      if (_disposed || _channel != null) return;
      await connect();
    });
  }

  static int _asInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse('$value') ?? 0;
  }

  void _reset() {
    _socketReady = false;
    _hasOwnerStatus = false;
    _isPlaybackOwner = true;
    _subscription?.cancel();
    _subscription = null;
    _channel = null;
    if (!_standaloneMode) _scheduleReconnect();
  }

  /// Reconcile the socket after Android resumes the Flutter process.
  /// We deliberately keep the existing connection when possible and ask the
  /// server for its authoritative state instead of trusting stale local state.
  Future<void> resume() async {
    await _ensureModeLoaded();
    if (_disposed || _standaloneMode) return;
    final auth = AuthService();
    await auth.refreshAccessToken();
    if (_channel == null) {
      await connect();
      return;
    }
    try {
      _channel!.sink.add(jsonEncode({'action': 'subscribe'}));
    } catch (_) {
      _reset();
      await connect();
    }
  }

  Future<void> sync({
    required Song? currentSong,
    required Duration position,
    required Duration? duration,
    required bool playing,
    required List<Song> queue,
    String? lyrics,
  }) async {
    await _ensureModeLoaded();
    if (_standaloneMode) return;
    await connect();
    final channel = _channel;
    if (channel == null) return;
    try {
      channel.sink.add(jsonEncode({
        'action': 'state',
        'state': {
          'track': currentSong == null ? null : {
            'id': currentSong.id,
            'title': currentSong.title,
            'artist': currentSong.artist,
            'album': currentSong.album,
            'image_url': currentSong.imageUrl,
            'media_url': currentSong.mediaUrl,
            'isrc': currentSong.isrc,
            'language': currentSong.language,
            'genre': currentSong.genre,
            'duration_seconds': currentSong.durationSeconds,
            'tempo': currentSong.tempo,
            'lyrics_id': currentSong.lyricsId,
          },
          'position_ms': position.inMilliseconds,
          'duration_ms': (duration ?? Duration.zero).inMilliseconds,
          'playing': playing,
          'queue': queue.map((song) => {
            'id': song.id,
            'title': song.title,
            'artist': song.artist,
            'album': song.album,
            'image_url': song.imageUrl,
            'media_url': song.mediaUrl,
            'isrc': song.isrc,
            'language': song.language,
            'genre': song.genre,
            'duration_seconds': song.durationSeconds,
            'tempo': song.tempo,
            'lyrics_id': song.lyricsId,
          }).toList(),
          'lyrics': lyrics,
        },
      }));
    } catch (_) {
      _reset();
    }
  }

  Future<void> publishPlaybackEvent(String event, {int? positionMs, String? trackId}) async {
    await _ensureModeLoaded();
    if (_standaloneMode) return;
    await connect();
    final channel = _channel;
    if (channel == null || !_isPlaybackOwner) return;
    try {
      channel.sink.add(jsonEncode({
        'action': 'playback_event',
        'event': event,
        if (positionMs != null) 'position_ms': positionMs,
        if (trackId != null) 'track_id': trackId,
      }));
    } catch (_) {
      _reset();
    }
  }

  Future<void> publishLyrics(String trackId, String lyrics) async {
    await _ensureModeLoaded();
    if (_standaloneMode) return;
    await connect();
    final channel = _channel;
    if (channel == null) return;
    try {
      channel.sink.add(jsonEncode({'action': 'lyrics', 'track_id': trackId, 'lyrics': lyrics}));
    } catch (_) {
      _reset();
    }
  }

  Future<void> publishQueue(List<Song> queue) async {
    await _ensureModeLoaded();
    if (_standaloneMode) return;
    await connect();
    final channel = _channel;
    if (channel == null) return;
    try {
      channel.sink.add(jsonEncode({
        'action': 'queue',
        'queue': queue.map((song) => {
          'id': song.id,
          'title': song.title,
          'artist': song.artist,
          'album': song.album,
          'image_url': song.imageUrl,
          'media_url': song.mediaUrl,
          'isrc': song.isrc,
          'language': song.language,
          'genre': song.genre,
          'duration_seconds': song.durationSeconds,
          'tempo': song.tempo,
          'lyrics_id': song.lyricsId,
        }).toList(),
      }));
    } catch (_) {
      _reset();
    }
  }


  Future<void> sendAppendTrack(Map<String, dynamic> track) async {
    await _ensureModeLoaded();
    if (_standaloneMode) return;
    await connect();
    final channel = _channel;
    if (channel == null) return;
    try {
      channel.sink.add(jsonEncode({
        'action': 'append_track',
        'track': track,
        'request_id': '${DateTime.now().microsecondsSinceEpoch}-append_track',
      }));
    } catch (_) {
      _reset();
    }
  }

  Future<void> sendPlayTrack(Map<String, dynamic> track) async {
    await _ensureModeLoaded();
    if (_standaloneMode) return;
    await connect();
    final channel = _channel;
    if (channel == null) return;
    try {
      channel.sink.add(jsonEncode({
        'action': 'play_track',
        'track': track,
        'request_id': '${DateTime.now().microsecondsSinceEpoch}-play_track',
      }));
    } catch (_) {
      _reset();
    }
  }

  void _sendCommandResult(String requestId, bool success, {String? error, String? replyChannel}) {
    final channel = _channel;
    if (channel == null || !_socketReady) return;
    try {
      channel.sink.add(jsonEncode({
        'action': 'command_result',
        'request_id': requestId,
        'success': success,
        if (error != null) 'error': error,
        if (replyChannel != null) 'reply_channel': replyChannel,
      }));
    } catch (_) {
      _reset();
    }
  }

  Future<void> sendCommand(String action, {int? positionMs}) async {
    await _ensureModeLoaded();
    if (_standaloneMode) return;
    await connect();
    final channel = _channel;
    if (channel == null) return;
    try {
      final payload = <String, dynamic>{
        'action': action,
        'request_id': '${DateTime.now().microsecondsSinceEpoch}-$action',
      };
      if (action == 'seek') payload['position_ms'] = positionMs ?? 0;
      channel.sink.add(jsonEncode(payload));
    } catch (_) {
      _reset();
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;
    _socketReady = false;
    _hasOwnerStatus = false;
  }
}
