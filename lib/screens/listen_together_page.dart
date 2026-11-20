import 'dart:async';
import 'dart:convert';
import 'dart:math' show sin;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:share_plus/share_plus.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/song.dart';
import '../services/audio_service.dart';
import '../services/auth_service.dart';
import '../services/monochrome_api.dart';
import '../theme/app_theme.dart';
import '../widgets/loopin_snackbar.dart';

class ListenTogetherPage extends StatefulWidget {
  const ListenTogetherPage({super.key});

  @override
  State<ListenTogetherPage> createState() => _ListenTogetherPageState();
}

class _ListenTogetherPageState extends State<ListenTogetherPage> {
  final _auth = AuthService();
  final _api = MonochromeApi();
  final _audio = GlobalAudioService();
  final _codeInput = TextEditingController();
  final _searchInput = TextEditingController();
  final _codeFocusNode = FocusNode();

  WebSocketChannel? _socket;
  Completer<void>? _welcomeCompleter;
  StreamSubscription? _messages;
  StreamSubscription? _playerStates;
  StreamSubscription? _indices;
  AudioPlayer? _listener;
  Timer? _heartbeat;
  Timer? _clockSyncTimer;
  Timer? _controlTimer;

  int _serverClockOffsetMs = 0;
  bool _hasClockOffset = false;
  int _stateApplyGeneration = 0;
  int _queueIndex = 0;
  final Map<String, String> _resolvedStreams = {};

  String? _code;
  String? _error;
  bool _host = false;
  bool _connected = false;
  bool _busy = false;
  bool _searching = false;
  bool _playing = false;

  List<Song> _queue = [];
  List<Song> _results = [];
  List<Map<String, dynamic>> _suggestions = [];
  Song? _current;
  String? _listenerTrackId;
  int _revision = 0;

  // UI state
  int _entryMode = 0; // 0 = Join, 1 = Host
  int _roomTab = 0; // 0 = Queue, 1 = Suggestions, 2 = Search

  @override
  void initState() {
    super.initState();
    _playerStates = _audio.playerStateStream.listen((s) {
      if (_host && mounted) {
        setState(() => _playing = s.playing);
        _publishSnapshot();
      }
    });
    _indices = _audio.currentIndexStream.listen((_) {
      if (_host) {
        _publishSnapshot(trackChanged: true);
      }
    });
  }

  @override
  void dispose() {
    _heartbeat?.cancel();
    _clockSyncTimer?.cancel();
    _controlTimer?.cancel();
    _messages?.cancel();
    _socket?.sink.close();
    _playerStates?.cancel();
    _indices?.cancel();
    _listener?.dispose();
    _codeInput.dispose();
    _searchInput.dispose();
    _codeFocusNode.dispose();
    super.dispose();
  }

  String _friendlyError(dynamic e, [String? code]) {
    final msg = e.toString();
    if (msg.contains('Sign in to') ||
        msg.contains('sign in') ||
        msg.contains('credentials were not provided') ||
        msg.contains('4401') ||
        msg.contains('401')) {
      return 'Please sign in to join or host a listening room.';
    }
    if (msg.contains('4404') ||
        msg.contains('404') ||
        msg.contains('not found') ||
        msg.contains('closed') ||
        msg.contains('rejected')) {
      return code != null
          ? 'Room "$code" was not found or has already ended.'
          : 'Room not found or has already ended.';
    }
    if (msg.contains('TimeoutException') || msg.contains('timed out')) {
      return 'Connection timed out. The server took too long to respond.';
    }
    if (msg.contains('WebSocketException') ||
        msg.contains('WebSocketChannelException') ||
        msg.contains('SocketException') ||
        msg.contains('failed to connect')) {
      return code != null
          ? 'Could not connect to room "$code". The room may no longer exist or the server is unavailable.'
          : 'Could not connect to the room server. Please check your internet connection.';
    }
    return msg.replaceFirst(RegExp(r'^(Exception|StateError|AuthException):\s*'), '');
  }

  Future<void> _create() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      var token = await _auth.accessToken();
      if (token == null || token.isEmpty) {
        throw StateError('Please sign in to host a listening room.');
      }
      await _auth.refreshAccessToken();
      final data = await _auth.post('/listen-together/rooms/', {});
      final code = data['code']?.toString() ?? '';
      if (code.isEmpty) throw StateError('Failed to allocate room code.');
      await _connect(code);
    } catch (e) {
      if (mounted) {
        final friendly = _friendlyError(e);
        setState(() => _error = friendly);
        CustomSnackBar.show(context, message: friendly, isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _join() async {
    final code = _codeInput.text.trim().toUpperCase();
    if (code.length != 6) {
      const msg = 'Please enter a 6-character room code.';
      setState(() => _error = msg);
      CustomSnackBar.show(
        context,
        message: msg,
        isError: true,
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      var token = await _auth.accessToken();
      if (token == null || token.isEmpty) {
        throw StateError('Please sign in to join a listening room.');
      }
      await _auth.refreshAccessToken();

      // Pre-check room existence via REST API to catch 404 or inactive rooms cleanly
      try {
        await _auth.get('/listen-together/rooms/$code/');
      } on AuthException catch (ae) {
        if (ae.statusCode == 404) {
          throw StateError('Room "$code" was not found or has already ended.');
        } else if (ae.statusCode == 401) {
          throw StateError('Your session has expired. Please sign in again.');
        }
        rethrow;
      }

      await _connect(code);
    } catch (e) {
      if (mounted) {
        final friendly = _friendlyError(e, code);
        setState(() => _error = friendly);
        CustomSnackBar.show(context, message: friendly, isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _connect(String code) async {
    var token = await _auth.accessToken();
    if (token == null || token.isEmpty) {
      throw StateError('Please sign in to use Listen Together.');
    }
    await _auth.refreshAccessToken();
    token = await _auth.accessToken() ?? token;

    final base = Uri.parse(AuthService.baseUrl);
    final uri = Uri(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      host: base.host,
      port: base.hasPort ? base.port : null,
      path: '/ws/listen-together/$code/',
      queryParameters: {'token': token},
    );
    final channel = WebSocketChannel.connect(uri);
    await channel.ready.timeout(const Duration(seconds: 12));
    await _messages?.cancel();
    await _socket?.sink.close();
    _socket = channel;
    _code = code;
    _welcomeCompleter = Completer<void>();
    _messages = channel.stream.listen(
      (raw) {
        unawaited(_onMessage(raw));
      },
      onError: (Object error) {
        if (_welcomeCompleter != null && !_welcomeCompleter!.isCompleted) {
          _welcomeCompleter!.completeError(error);
        }
        if (mounted) {
          final friendly = _friendlyError(error, code);
          setState(() {
            _connected = false;
            _error = friendly;
          });
          CustomSnackBar.show(
            context,
            message: friendly,
            isError: true,
          );
        }
      },
      onDone: () {
        if (_welcomeCompleter != null && !_welcomeCompleter!.isCompleted) {
          _welcomeCompleter!.completeError(
            StateError('Room connection was rejected or closed by host.'),
          );
        }
        if (mounted) {
          setState(() => _connected = false);
        }
      },
    );
    try {
      await _welcomeCompleter!.future.timeout(const Duration(seconds: 8));
    } catch (_) {
      await channel.sink.close();
      await _messages?.cancel();
      _messages = null;
      _socket = null;
      _welcomeCompleter = null;
      _code = null;
      rethrow;
    }
    if (mounted) {
      setState(() {
        _connected = true;
        _error = null;
      });
      CustomSnackBar.show(context, message: 'Connected to room $code');
    }
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_host) {
        _publishSnapshot();
      }
    });
    _sendClockPing();
    _clockSyncTimer?.cancel();
    _clockSyncTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _sendClockPing(),
    );
  }

  int _int(dynamic value) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? 0;

  void _sendClockPing() {
    _send({
      'action': 'ping',
      'client_time_ms': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Song? _song(dynamic value) =>
      value is Map ? Song.fromJson(Map<String, dynamic>.from(value)) : null;

  List<Song> _songs(dynamic value) => value is List
      ? value
            .whereType<Map>()
            .map((e) => Song.fromJson(Map<String, dynamic>.from(e)))
            .toList()
      : <Song>[];

  void _send(Map<String, dynamic> value) {
    if (_socket != null && _connected) {
      _socket!.sink.add(jsonEncode(value));
    }
  }

  Future<void> _onMessage(dynamic raw) async {
    try {
      final decoded = jsonDecode(raw.toString());
      if (decoded is! Map) return;
      final data = Map<String, dynamic>.from(decoded);
      final type = data['type'];
      if (type == 'pong') {
        final sent = _int(data['client_time_ms']);
        final received = DateTime.now().millisecondsSinceEpoch;
        final server = _int(data['server_time_ms']);
        if (sent > 0 && server > 0 && received >= sent) {
          final estimate = server - ((sent + received) ~/ 2);
          _serverClockOffsetMs = _hasClockOffset
              ? ((_serverClockOffsetMs * 3) + estimate) ~/ 4
              : estimate;
          _hasClockOffset = true;
        }
        return;
      }
      if (type == 'welcome') {
        final state = Map<String, dynamic>.from(data['state'] ?? {});
        if (mounted) {
          setState(() {
            _host = data['is_host'] == true;
            _code = data['code']?.toString();
            _suggestions = List<Map<String, dynamic>>.from(
              data['suggestions'] ?? [],
            );
            _queue = _songs(state['queue']);
            _current = _song(state['track']);
            _playing = state['playing'] == true;
            _revision = _int(state['revision']);
            _queueIndex = _int(state['current_index']);
          });
        }
        _preloadUpcoming(_queue, _queueIndex);
        if (_current != null && !_host) {
          unawaited(_applyState(state, _int(state['server_time_ms'])));
        }
        if (_welcomeCompleter != null && !_welcomeCompleter!.isCompleted) {
          _welcomeCompleter!.complete();
        }
      } else if (type == 'playback' || type == 'snapshot') {
        final state = Map<String, dynamic>.from(data['state'] ?? {});
        if (_int(state['revision']) <= _revision) return;
        _revision = _int(state['revision']);
        if (mounted) {
          setState(() {
            _current = _song(state['track']);
            _playing = state['playing'] == true;
            _queue = _songs(state['queue']);
            _queueIndex = _int(state['current_index']);
          });
        }
        _preloadUpcoming(_queue, _queueIndex);
        final target = type == 'playback'
            ? _int(data['target_epoch_ms'] ?? state['target_epoch_ms'])
            : _int(state['server_time_ms']);
        if (!_host) {
          unawaited(_applyState(state, target));
        }
      } else if (type == 'queue_update') {
        final state = Map<String, dynamic>.from(data['state'] ?? {});
        _revision = _int(state['revision']);
        if (mounted) {
          setState(() {
            _queue = _songs(state['queue']);
            _queueIndex = _int(state['current_index']);
          });
        }
        _preloadUpcoming(_queue, _queueIndex);
      } else if (type == 'suggestions' || type == 'suggestion_decided') {
        if (mounted) {
          setState(
            () => _suggestions = List<Map<String, dynamic>>.from(
              data['suggestions'] ?? [],
            ),
          );
        }
      } else if (type == 'room_ended') {
        await _leave(localOnly: true);
        if (mounted) {
          setState(() => _error = 'The host ended this room.');
          CustomSnackBar.show(context, message: 'The host ended this room.');
        }
      } else if (type == 'error' && mounted) {
        final msg = data['message']?.toString() ?? 'An error occurred';
        setState(() => _error = msg);
        CustomSnackBar.show(context, message: msg, isError: true);
      }
    } catch (e) {
      debugPrint('Listen Together message error: $e');
    }
  }

  Future<void> _applyState(
    Map<String, dynamic> state,
    int targetEpochMs,
  ) async {
    final song = _song(state['track']);
    if (song == null) return;
    final generation = ++_stateApplyGeneration;
    final player = _host ? await _audio.player : (_listener ??= AudioPlayer());
    final trackChanged = _host
        ? false
        : (_listenerTrackId != song.id || player.audioSource == null);
    if (trackChanged) {
      final url =
          _resolvedStreams.remove(song.id) ?? await _api.resolveStream(song);
      if (url == null || url.isEmpty) {
        throw StateError('Could not resolve ${song.title}');
      }
      if (generation != _stateApplyGeneration) return;
      await player.setUrl(url, preload: true);
      _listenerTrackId = song.id;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final targetServer = targetEpochMs > 0
        ? targetEpochMs
        : _int(state['server_time_ms']);
    final targetLocal = targetServer > 0
        ? targetServer - _serverClockOffsetMs
        : now;
    final elapsed = targetServer > 0
        ? (now + _serverClockOffsetMs - targetServer).clamp(0, 10000).toInt()
        : 0;
    final position =
        _int(state['position_ms']) + (state['playing'] == true ? elapsed : 0);
    final signedDrift = player.position.inMilliseconds - position;
    final drift = signedDrift.abs();
    if (generation != _stateApplyGeneration) return;
    if (trackChanged || drift > 180) {
      await player.seek(Duration(milliseconds: position));
      await player.setSpeed(1.0);
    } else if (state['playing'] == true && drift >= 45) {
      final correction = (1.0 - signedDrift / 12000)
          .clamp(0.985, 1.015)
          .toDouble();
      await player.setSpeed(correction);
    } else if (player.speed != 1.0) {
      await player.setSpeed(1.0);
    }
    if (generation != _stateApplyGeneration) return;
    _controlTimer?.cancel();
    final delay = (targetLocal - DateTime.now().millisecondsSinceEpoch)
        .clamp(0, 3000)
        .toInt();
    _controlTimer = Timer(Duration(milliseconds: delay), () {
      if (generation != _stateApplyGeneration) return;
      if (state['playing'] == true) {
        if (!player.playing) unawaited(player.play());
      } else if (player.playing) {
        unawaited(player.pause());
      }
    });
  }

  Future<void> _publishSnapshot({bool trackChanged = false}) async {
    if (!_host || !_connected) return;
    try {
      final player = await _audio.player;
      final index = _audio.currentIndex;
      final queue = _audio.queue;
      final song = index != null && index >= 0 && index < queue.length
          ? queue[index]
          : null;
      if (song != null && (trackChanged || song.id != _current?.id)) {
        _current = song;
        _send({
          'action': 'playback',
          'event': 'track',
          'track': song.toJson(),
          'target_epoch_ms':
              DateTime.now().millisecondsSinceEpoch +
              _serverClockOffsetMs +
              150,
        });
      }
      _send({
        'action': 'heartbeat',
        'position_ms': player.position.inMilliseconds,
        'sampled_at_server_ms':
            DateTime.now().millisecondsSinceEpoch + _serverClockOffsetMs,
        'playing': player.playing,
        'track': song?.toJson(),
        'queue': queue.map((s) => s.toJson()).toList(),
        'current_index': index ?? 0,
      });
      if (mounted) {
        setState(() {
          _queue = List<Song>.from(queue);
          _current = song;
          _playing = player.playing;
        });
      }
    } catch (_) {}
  }

  void _preloadUpcoming(List<Song> queue, int currentIndex) {
    if (_host || !_connected || queue.isEmpty) return;
    for (final song in queue.skip(currentIndex + 1).take(3)) {
      if (_resolvedStreams.containsKey(song.id)) continue;
      unawaited(
        _api
            .resolveStream(song)
            .then((url) {
              if (url != null && url.isNotEmpty && mounted) {
                _resolvedStreams[song.id] = url;
              }
            })
            .catchError((Object _) {}),
      );
    }
  }

  Future<void> _search() async {
    final query = _searchInput.text.trim();
    if (query.length < 2) return;
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final found = await _api.search(query, pages: 1, limit: 15);
      if (mounted) setState(() => _results = found);
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Search failed: ${e.toString()}');
        CustomSnackBar.show(context, message: 'Search failed', isError: true);
      }
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _suggest(Song song) {
    _send({'action': 'suggest', 'track': song.toJson()});
    CustomSnackBar.show(context, message: 'Suggested "${song.title}" to host');
  }

  Future<void> _addSongDirectly(Song song) async {
    if (!_host) return;
    try {
      final url = await _api.resolveStream(song);
      if (url == null) throw StateError('No playable stream found.');
      final playable = Song(
        id: song.id,
        title: song.title,
        artist: song.artist,
        album: song.album,
        imageUrl: song.imageUrl,
        mediaUrl: url,
        isrc: song.isrc,
        language: song.language,
        durationSeconds: song.durationSeconds,
        tempo: song.tempo,
        genre: song.genre,
        lyricsId: song.lyricsId,
      );
      await _audio.appendSongToQueue(playable);
      final updatedQueue = List<Song>.from(_audio.queue);
      if (!updatedQueue.any((entry) => entry.id == playable.id)) {
        updatedQueue.add(playable);
      }
      if (mounted) setState(() => _queue = updatedQueue);
      _send({
        'action': 'queue_update',
        'queue': updatedQueue.map((s) => s.toJson()).toList(),
        'current_index': _audio.currentIndex ?? 0,
      });
      _publishSnapshot(trackChanged: false);
      if (mounted) {
        CustomSnackBar.show(context, message: 'Added "${song.title}" to queue');
      }
    } catch (e) {
      if (mounted) {
        CustomSnackBar.show(context, message: e.toString(), isError: true);
      }
    }
  }

  Future<void> _decide(Map<String, dynamic> item, bool add) async {
    final song = _song(item['track']);
    if (song == null) return;
    if (!add) {
      _send({
        'action': 'suggestion_decision',
        'suggestion_id': item['id'],
        'decision': 'dismissed',
      });
      return;
    }
    try {
      final url = await _api.resolveStream(song);
      if (url == null) throw StateError('No playable stream found.');
      final playable = Song(
        id: song.id,
        title: song.title,
        artist: song.artist,
        album: song.album,
        imageUrl: song.imageUrl,
        mediaUrl: url,
        isrc: song.isrc,
        language: song.language,
        durationSeconds: song.durationSeconds,
        tempo: song.tempo,
        genre: song.genre,
        lyricsId: song.lyricsId,
      );
      await _audio.appendSongToQueue(playable);
      final updatedQueue = List<Song>.from(_audio.queue);
      if (!updatedQueue.any((entry) => entry.id == playable.id)) {
        updatedQueue.add(playable);
      }
      if (mounted) setState(() => _queue = updatedQueue);
      _send({
        'action': 'suggestion_decision',
        'suggestion_id': item['id'],
        'decision': 'added',
        'queue': updatedQueue.map((s) => s.toJson()).toList(),
        'current_index': _audio.currentIndex ?? 0,
      });
      if (mounted) {
        CustomSnackBar.show(
          context,
          message: 'Accepted "${song.title}" to queue',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
        CustomSnackBar.show(context, message: e.toString(), isError: true);
      }
    }
  }

  Future<void> _toggle() async {
    final player = await _audio.player;
    final wasPlaying = player.playing;
    final now = DateTime.now().millisecondsSinceEpoch;
    const leadMs = 220;
    final targetLocal = now + leadMs;
    final targetServer = targetLocal + _serverClockOffsetMs;
    final position = player.position.inMilliseconds + (wasPlaying ? leadMs : 0);

    _controlTimer?.cancel();
    _controlTimer = Timer(const Duration(milliseconds: leadMs), () {
      if (wasPlaying) {
        unawaited(player.pause());
      } else {
        unawaited(player.play());
      }
    });
    if (mounted) setState(() => _playing = !wasPlaying);
    _send({
      'action': 'playback',
      'event': wasPlaying ? 'pause' : 'play',
      'position_ms': position,
      'target_epoch_ms': targetServer,
    });
  }

  Future<void> _next() async {
    final index = _audio.currentIndex ?? 0;
    if (index + 1 < _audio.queue.length) {
      await _audio.playAtIndex(index + 1);
      await _publishSnapshot(trackChanged: true);
    }
  }

  Future<void> _confirmLeave() async {
    final isHost = _host;
    final title = isHost ? 'End Listening Room?' : 'Leave Room?';
    final content = isHost
        ? 'This will disconnect all listeners and close the session.'
        : 'You will stop receiving synchronized audio from the host.';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C22),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: Colors.white.withValues(alpha: 0.15),
            width: 1,
          ),
        ),
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          content,
          style: const TextStyle(color: AppColors.muted, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isHost ? Colors.redAccent : AppColors.accent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(isHost ? 'End Room' : 'Leave Room'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _leave();
      if (mounted) {
        CustomSnackBar.show(
          context,
          message: isHost ? 'Room ended' : 'Left room',
        );
      }
    }
  }

  Future<void> _leave({bool localOnly = false}) async {
    if (!localOnly && _host) {
      _send({'action': 'end_room'});
    }
    _heartbeat?.cancel();
    _clockSyncTimer?.cancel();
    _controlTimer?.cancel();
    _stateApplyGeneration++;
    _resolvedStreams.clear();
    await _messages?.cancel();
    await _socket?.sink.close();
    _messages = null;
    _socket = null;
    _welcomeCompleter = null;
    await _listener?.stop();
    if (mounted) {
      setState(() {
        _code = null;
        _connected = false;
        _host = false;
        _suggestions = [];
        _queue = [];
        _current = null;
        _listener = null;
        _listenerTrackId = null;
        _playing = false;
        _results = [];
        _searchInput.clear();
        _codeInput.clear();
      });
    }
  }

  String _formatDuration(int? seconds) {
    if (seconds == null || seconds <= 0) return '--:--';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: _code == null ? _buildEntryView() : _buildRoomView(),
      ),
    );
  }

  // ==========================================
  // ENTRY SCREEN (JOIN OR HOST)
  // ==========================================

  Widget _buildEntryView() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      children: [
        const SizedBox(height: 12),
        // Header
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppColors.accent.withValues(alpha: 0.25),
                width: 1,
              ),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.sensors_rounded, color: AppColors.accent, size: 16),
                SizedBox(width: 8),
                Text(
                  'REAL-TIME AUDIO SHARING',
                  style: TextStyle(
                    color: AppColors.accent,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Center(
          child: Text(
            'Listen Together',
            style: AppFonts.display(
              fontSize: 48,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 6),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            'Share music synchronously with friends across devices with sub-second clock alignment.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.muted,
              fontSize: 13,
              height: 1.45,
            ),
          ),
        ),
        const SizedBox(height: 28),

        // Segmented Mode Switcher (Join Room / Host Session)
        _buildErrorBanner(),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _entryMode = 0);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: _entryMode == 0
                          ? AppColors.surfaceElevated
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      border: _entryMode == 0
                          ? Border.all(
                              color: AppColors.accent.withValues(alpha: 0.4),
                              width: 1.2,
                            )
                          : null,
                      boxShadow: _entryMode == 0
                          ? [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.login_rounded,
                          size: 16,
                          color: _entryMode == 0
                              ? AppColors.accent
                              : AppColors.muted,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Join a Room',
                          style: TextStyle(
                            color: _entryMode == 0
                                ? Colors.white
                                : AppColors.muted,
                            fontWeight: _entryMode == 0
                                ? FontWeight.bold
                                : FontWeight.w500,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _entryMode = 1);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: _entryMode == 1
                          ? AppColors.surfaceElevated
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      border: _entryMode == 1
                          ? Border.all(
                              color: AppColors.accent.withValues(alpha: 0.4),
                              width: 1.2,
                            )
                          : null,
                      boxShadow: _entryMode == 1
                          ? [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.wifi_tethering_rounded,
                          size: 16,
                          color: _entryMode == 1
                              ? AppColors.accent
                              : AppColors.muted,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Host Session',
                          style: TextStyle(
                            color: _entryMode == 1
                                ? Colors.white
                                : AppColors.muted,
                            fontWeight: _entryMode == 1
                                ? FontWeight.bold
                                : FontWeight.w500,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Mode Content
        if (_entryMode == 0) _buildJoinCard() else _buildHostCard(),

        const SizedBox(height: 32),

        // How it works / Feature highlights
        _buildFeaturesList(),
        const SizedBox(height: 30),
      ],
    );
  }

  Widget _buildJoinCard() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.key_rounded,
                  color: AppColors.accent,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Enter Room Code',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Ask the host for their 6-character room code',
                    style: TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Clean, modern room code input
          Container(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: _codeInput.text.isNotEmpty
                    ? AppColors.accent.withValues(alpha: 0.5)
                    : Colors.white.withValues(alpha: 0.12),
                width: 1.2,
              ),
            ),
            child: TextField(
              controller: _codeInput,
              focusNode: _codeFocusNode,
              textCapitalization: TextCapitalization.characters,
              maxLength: 6,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w800,
                letterSpacing: 8,
              ),
              decoration: InputDecoration(
                hintText: 'ENTER CODE',
                hintStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.25),
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 4,
                ),
                counterText: '',
                prefixIcon: const Padding(
                  padding: EdgeInsets.only(left: 14, right: 6),
                  child: Icon(Icons.tag_rounded, color: AppColors.accent, size: 22),
                ),
                prefixIconConstraints: const BoxConstraints(minWidth: 42, minHeight: 42),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_codeInput.text.isNotEmpty)
                      IconButton(
                        tooltip: 'Clear',
                        icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.muted),
                        onPressed: () {
                          _codeInput.clear();
                          setState(() {});
                        },
                      )
                    else
                      IconButton(
                        tooltip: 'Paste from clipboard',
                        icon: const Icon(Icons.content_paste_rounded, size: 18, color: AppColors.muted),
                        onPressed: () async {
                          final data = await Clipboard.getData(Clipboard.kTextPlain);
                          if (data?.text != null) {
                            final clean = data!.text!.trim().toUpperCase().replaceAll(
                              RegExp(r'[^A-Z0-9]'),
                              '',
                            );
                            if (clean.isNotEmpty) {
                              final target = clean.length > 6 ? clean.substring(0, 6) : clean;
                              _codeInput.text = target;
                              setState(() {});
                              HapticFeedback.lightImpact();
                              if (target.length == 6) {
                                _join();
                              }
                            }
                          }
                        },
                      ),
                    const SizedBox(width: 6),
                  ],
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]')),
              ],
              onChanged: (val) {
                setState(() {});
                if (val.length == 6) {
                  _join();
                }
              },
              onSubmitted: (_) => _join(),
            ),
          ),
          const SizedBox(height: 12),

          // Quick actions / helper text
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${_codeInput.text.length}/6 characters',
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
              const SizedBox(width: 14),
              GestureDetector(
                onTap: () async {
                  final data = await Clipboard.getData(Clipboard.kTextPlain);
                  if (data?.text != null) {
                    final clean = data!.text!.trim().toUpperCase().replaceAll(
                      RegExp(r'[^A-Z0-9]'),
                      '',
                    );
                    if (clean.isNotEmpty) {
                      final target = clean.length > 6 ? clean.substring(0, 6) : clean;
                      _codeInput.text = target;
                      setState(() {});
                      HapticFeedback.lightImpact();
                      if (target.length == 6) {
                        _join();
                      }
                    }
                  }
                },
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.content_paste_rounded, size: 13, color: AppColors.accent),
                    SizedBox(width: 4),
                    Text(
                      'Paste code',
                      style: TextStyle(color: AppColors.accent, fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const SizedBox(height: 10),

          // Submit Button
          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: _busy ? null : _join,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: _busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.2,
                      ),
                    )
                  : const Text(
                      'Join Room',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHostCard() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.wifi_tethering_rounded,
                  color: AppColors.accent,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Host a Listening Party',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Broadcast playback & manage queue for friends',
                    style: TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
            ),
            child: Column(
              children: [
                _buildHostFeatureBullet(
                  Icons.playlist_play_rounded,
                  'You control track changes, scrubbing & pausing',
                ),
                const SizedBox(height: 10),
                _buildHostFeatureBullet(
                  Icons.mark_chat_read_rounded,
                  'Listeners can send song suggestions to your queue',
                ),
                const SizedBox(height: 10),
                _buildHostFeatureBullet(
                  Icons.offline_bolt_rounded,
                  'Upcoming songs are preloaded on listener devices',
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: _busy ? null : _create,
              icon: _busy
                  ? const SizedBox.shrink()
                  : const Icon(Icons.add_rounded, size: 20),
              label: _busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.2,
                      ),
                    )
                  : const Text(
                      'Create Room',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHostFeatureBullet(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: AppColors.accent),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 12,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFeaturesList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 12),
          child: Text(
            'HOW IT WORKS',
            style: TextStyle(
              color: AppColors.muted,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
        ),
        _buildFeatureItem(
          icon: Icons.sync_rounded,
          title: 'Sub-Second Audio Clock',
          subtitle:
              'Continuous NTP-style ping calculations correct audio drift across devices.',
        ),
        const SizedBox(height: 10),
        _buildFeatureItem(
          icon: Icons.group_rounded,
          title: 'Shared Song Requests',
          subtitle:
              'Everyone in the room can search and suggest songs without interrupting playback.',
        ),
        const SizedBox(height: 10),
        _buildFeatureItem(
          icon: Icons.share_rounded,
          title: 'Instant 6-Letter Codes',
          subtitle:
              'No complex logins required for your friends to jump into the room.',
        ),
      ],
    );
  }

  Widget _buildFeatureItem({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppColors.accent, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 11,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // ACTIVE ROOM SCREEN
  // ==========================================

  Widget _buildRoomView() {
    return Column(
      children: [
        // Top Room Bar
        _buildRoomHeaderBar(),

        // Scrollable content
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 30),
            children: [
              _buildErrorBanner(),
              // Room Code Card
              _buildRoomCodeCard(),
              const SizedBox(height: 16),

              // Now Playing Section
              _buildNowPlayingCard(),
              const SizedBox(height: 20),

              // Room Tabs Switcher
              _buildRoomTabs(),
              const SizedBox(height: 16),

              // Tab View Content
              if (_roomTab == 0)
                _buildQueueTab()
              else if (_roomTab == 1)
                _buildSuggestionsTab()
              else
                _buildSearchTab(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRoomHeaderBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          // Leave room action button
          IconButton.filledTonal(
            onPressed: _confirmLeave,
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.06),
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.arrow_back_rounded, size: 20),
            tooltip: _host ? 'End Room' : 'Leave Room',
          ),
          const SizedBox(width: 10),

          // Room Status Pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _connected
                  ? Colors.greenAccent.withValues(alpha: 0.12)
                  : Colors.orangeAccent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _connected
                    ? Colors.greenAccent.withValues(alpha: 0.3)
                    : Colors.orangeAccent.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.circle,
                  color: _connected ? Colors.greenAccent : Colors.orangeAccent,
                  size: 8,
                ),
                const SizedBox(width: 6),
                Text(
                  _connected ? 'CONNECTED' : 'RECONNECTING',
                  style: TextStyle(
                    color: _connected
                        ? Colors.greenAccent
                        : Colors.orangeAccent,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                  ),
                ),
                if (_hasClockOffset) ...[
                  const SizedBox(width: 6),
                  Text(
                    '• ${_serverClockOffsetMs.abs()}ms',
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 10,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Spacer(),

          // Role Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _host
                  ? AppColors.accent.withValues(alpha: 0.15)
                  : Colors.blueAccent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _host
                    ? AppColors.accent.withValues(alpha: 0.3)
                    : Colors.blueAccent.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _host ? Icons.star_rounded : Icons.headphones_rounded,
                  size: 14,
                  color: _host ? AppColors.accent : Colors.blueAccent,
                ),
                const SizedBox(width: 5),
                Text(
                  _host ? 'HOST' : 'LISTENER',
                  style: TextStyle(
                    color: _host ? AppColors.accent : Colors.blueAccent,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoomCodeCard() {
    final code = _code ?? '';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.surfaceElevated,
            AppColors.surfaceElevated.withValues(alpha: 0.85),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.accent.withValues(alpha: 0.3),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.accent.withValues(alpha: 0.08),
            blurRadius: 18,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Text(
                      'ROOM CODE',
                      style: TextStyle(
                        color: AppColors.muted,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.4,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  code,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 6,
                  ),
                ),
              ],
            ),
          ),
          IconButton.filledTonal(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: code));
              HapticFeedback.lightImpact();
              CustomSnackBar.show(
                context,
                message: 'Room code copied to clipboard!',
              );
            },
            tooltip: 'Copy Code',
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.08),
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.copy_rounded, size: 18),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: () {
              HapticFeedback.lightImpact();
              Share.share(
                'Join my synchronized listening room on Loopin! 🎧\nRoom code: $code',
              );
            },
            tooltip: 'Share Invite',
            style: IconButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.share_rounded, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _buildNowPlayingCard() {
    final song = _current;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Artwork with live equalizer overlay
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: song?.imageUrl.isNotEmpty == true
                        ? Image.network(
                            song!.imageUrl,
                            width: 68,
                            height: 68,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _art(68),
                          )
                        : _art(68),
                  ),
                  if (_playing)
                    Positioned(
                      right: 6,
                      bottom: 6,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: _EqualizerBars(
                          isPlaying: _playing,
                          color: AppColors.accent,
                          size: 14,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'NOW STREAMING',
                        style: TextStyle(
                          color: AppColors.accent,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      song?.title ?? 'Waiting for host to play music',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      song?.artist ?? 'Playback begins as soon as track starts',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(color: AppColors.divider, height: 1),
          const SizedBox(height: 10),
          if (_host)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.tune_rounded, color: AppColors.muted, size: 16),
                    SizedBox(width: 6),
                    Text(
                      'Host controls',
                      style: TextStyle(color: AppColors.muted, fontSize: 11),
                    ),
                  ],
                ),
                Row(
                  children: [
                    IconButton(
                      onPressed: _next,
                      icon: const Icon(
                        Icons.skip_next_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.accent.withValues(alpha: 0.35),
                            blurRadius: 14,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: IconButton.filled(
                        onPressed: _toggle,
                        style: IconButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.all(10),
                        ),
                        icon: Icon(
                          _playing
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          size: 26,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            )
          else
            Row(
              children: [
                Icon(
                  _playing
                      ? Icons.volume_up_rounded
                      : Icons.pause_circle_outline_rounded,
                  color: _playing ? AppColors.accent : AppColors.muted,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Text(
                  _playing
                      ? 'In sync with host playback'
                      : 'Host paused playback',
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
                const Spacer(),
                const Text(
                  'Controlled by host',
                  style: TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildRoomTabs() {
    final tabs = [
      {
        'title': 'Queue',
        'badge': _queue.length,
        'icon': Icons.queue_music_rounded,
      },
      {
        'title': 'Requests',
        'badge': _suggestions.length,
        'icon': Icons.recommend_rounded,
      },
      {
        'title': _host ? 'Add Songs' : 'Suggest',
        'badge': 0,
        'icon': Icons.search_rounded,
      },
    ];

    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: List.generate(tabs.length, (index) {
          final isSelected = _roomTab == index;
          final tab = tabs[index];
          final badge = tab['badge'] as int;

          return Expanded(
            child: GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _roomTab = index);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.surfaceElevated
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: isSelected
                      ? Border.all(
                          color: AppColors.accent.withValues(alpha: 0.35),
                        )
                      : null,
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      tab['icon'] as IconData,
                      size: 15,
                      color: isSelected ? AppColors.accent : AppColors.muted,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      tab['title'] as String,
                      style: TextStyle(
                        color: isSelected ? Colors.white : AppColors.muted,
                        fontSize: 12,
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.w500,
                      ),
                    ),
                    if (badge > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected ? AppColors.accent : Colors.white12,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          badge.toString(),
                          style: TextStyle(
                            color: isSelected ? Colors.white : AppColors.muted,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  // --- TAB 0: QUEUE ---
  Widget _buildQueueTab() {
    if (_queue.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
        alignment: Alignment.center,
        child: Column(
          children: [
            const Icon(
              Icons.music_off_rounded,
              color: Colors.white24,
              size: 44,
            ),
            const SizedBox(height: 12),
            const Text(
              'Queue is empty',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _host
                  ? 'Search and add tracks to start jamming with friends!'
                  : 'The host has not added any songs yet.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),
            if (_host) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => setState(() => _roomTab = 2),
                icon: const Icon(Icons.search_rounded, size: 16),
                label: const Text('Find Songs'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent,
                ),
              ),
            ],
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'UP NEXT (${_queue.length})',
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              if (_host)
                TextButton.icon(
                  onPressed: () => setState(() => _roomTab = 2),
                  icon: const Icon(
                    Icons.add_rounded,
                    size: 14,
                    color: AppColors.accent,
                  ),
                  label: const Text(
                    'Add Song',
                    style: TextStyle(color: AppColors.accent, fontSize: 11),
                  ),
                ),
            ],
          ),
        ),
        ..._queue.asMap().entries.map((entry) {
          final index = entry.key;
          final song = entry.value;
          final isPlayingNow = _current?.id == song.id;

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: isPlayingNow
                  ? AppColors.accent.withValues(alpha: 0.1)
                  : AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isPlayingNow
                    ? AppColors.accent.withValues(alpha: 0.35)
                    : Colors.white.withValues(alpha: 0.04),
              ),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 2,
              ),
              leading: Stack(
                alignment: Alignment.center,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: song.imageUrl.isNotEmpty
                        ? Image.network(
                            song.imageUrl,
                            width: 44,
                            height: 44,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _art(44),
                          )
                        : _art(44),
                  ),
                  if (isPlayingNow && _playing)
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: const _EqualizerBars(isPlaying: true, size: 14),
                    ),
                ],
              ),
              title: Text(
                song.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isPlayingNow ? AppColors.accent : Colors.white,
                  fontSize: 13,
                  fontWeight: isPlayingNow ? FontWeight.bold : FontWeight.w500,
                ),
              ),
              subtitle: Text(
                song.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.muted, fontSize: 11),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _formatDuration(song.durationSeconds),
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.06),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '${index + 1}',
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  // --- TAB 1: SUGGESTIONS ---
  Widget _buildSuggestionsTab() {
    if (_suggestions.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
        alignment: Alignment.center,
        child: Column(
          children: [
            const Icon(
              Icons.recommend_outlined,
              color: Colors.white24,
              size: 44,
            ),
            const SizedBox(height: 12),
            const Text(
              'No suggestions yet',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _host
                  ? 'Listener suggestions will pop up here for your approval.'
                  : 'Suggest songs to the host using the search tab!',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => setState(() => _roomTab = 2),
              icon: const Icon(Icons.search_rounded, size: 16),
              label: const Text('Search & Suggest'),
              style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Text(
            'PENDING REQUESTS (${_suggestions.length})',
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
        ),
        ..._suggestions.map((item) {
          final song = _song(item['track']);
          if (song == null) return const SizedBox.shrink();
          final user = item['user']?.toString() ?? 'A listener';

          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.person_outline_rounded,
                      size: 14,
                      color: AppColors.accent,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Suggested by $user',
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: song.imageUrl.isNotEmpty
                          ? Image.network(
                              song.imageUrl,
                              width: 44,
                              height: 44,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _art(44),
                            )
                          : _art(44),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            song.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            song.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_host) ...[
                      IconButton.filledTonal(
                        onPressed: () => _decide(item, true),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.greenAccent.withValues(
                            alpha: 0.15,
                          ),
                          foregroundColor: Colors.greenAccent,
                        ),
                        icon: const Icon(Icons.check_rounded, size: 18),
                        tooltip: 'Add to Queue',
                      ),
                      const SizedBox(width: 6),
                      IconButton.filledTonal(
                        onPressed: () => _decide(item, false),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.redAccent.withValues(
                            alpha: 0.15,
                          ),
                          foregroundColor: Colors.redAccent,
                        ),
                        icon: const Icon(Icons.close_rounded, size: 18),
                        tooltip: 'Dismiss',
                      ),
                    ] else
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'Pending',
                          style: TextStyle(
                            color: AppColors.muted,
                            fontSize: 11,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  // --- TAB 2: SEARCH & ADD/SUGGEST ---
  Widget _buildSearchTab() {
    return Column(
      children: [
        // Search Bar
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Row(
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Icon(
                  Icons.search_rounded,
                  color: AppColors.muted,
                  size: 20,
                ),
              ),
              Expanded(
                child: TextField(
                  controller: _searchInput,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  onSubmitted: (_) => _search(),
                  decoration: const InputDecoration(
                    hintText: 'Search songs, artists, albums...',
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              if (_searchInput.text.isNotEmpty)
                IconButton(
                  onPressed: () {
                    _searchInput.clear();
                    setState(() => _results = []);
                  },
                  icon: const Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: AppColors.muted,
                  ),
                ),
              IconButton(
                onPressed: _searching ? null : _search,
                icon: const Icon(
                  Icons.arrow_forward_rounded,
                  color: AppColors.accent,
                  size: 20,
                ),
              ),
            ],
          ),
        ),
        if (_searching)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: LinearProgressIndicator(
              color: AppColors.accent,
              backgroundColor: Colors.transparent,
              minHeight: 2,
            ),
          ),
        const SizedBox(height: 14),

        if (_results.isEmpty && !_searching)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
            alignment: Alignment.center,
            child: Column(
              children: [
                const Icon(
                  Icons.queue_music_rounded,
                  color: Colors.white24,
                  size: 40,
                ),
                const SizedBox(height: 10),
                Text(
                  _host
                      ? 'Find songs to add to the queue'
                      : 'Search tracks to suggest to the host',
                  style: const TextStyle(color: AppColors.muted, fontSize: 13),
                ),
              ],
            ),
          ),

        // Search Results List
        ..._results.map((song) {
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 2,
              ),
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: song.imageUrl.isNotEmpty
                    ? Image.network(
                        song.imageUrl,
                        width: 44,
                        height: 44,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _art(44),
                      )
                    : _art(44),
              ),
              title: Text(
                song.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Text(
                '${song.artist} • ${_formatDuration(song.durationSeconds)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.muted, fontSize: 11),
              ),
              trailing: _host
                  ? FilledButton.tonalIcon(
                      onPressed: () => _addSongDirectly(song),
                      icon: const Icon(Icons.add_rounded, size: 16),
                      label: const Text('Add'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accent.withValues(
                          alpha: 0.15,
                        ),
                        foregroundColor: AppColors.accent,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        textStyle: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    )
                  : FilledButton.tonalIcon(
                      onPressed: () => _suggest(song),
                      icon: const Icon(Icons.send_rounded, size: 14),
                      label: const Text('Suggest'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accent.withValues(
                          alpha: 0.15,
                        ),
                        foregroundColor: AppColors.accent,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        textStyle: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildErrorBanner() {
    if (_error == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.redAccent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: Colors.redAccent,
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _error!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 12),
            ),
          ),
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: const Icon(
              Icons.close_rounded,
              color: Colors.redAccent,
              size: 16,
            ),
            onPressed: () => setState(() => _error = null),
          ),
        ],
      ),
    );
  }

  Widget _art([double size = 64]) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(8),
    ),
    child: const Icon(Icons.music_note_rounded, color: AppColors.muted),
  );
}

// ==========================================
// ANIMATED EQUALIZER COMPONENT
// ==========================================

class _EqualizerBars extends StatefulWidget {
  final bool isPlaying;
  final Color color;
  final double size;

  const _EqualizerBars({
    required this.isPlaying,
    this.color = AppColors.accent,
    this.size = 18,
  });

  @override
  State<_EqualizerBars> createState() => _EqualizerBarsState();
}

class _EqualizerBarsState extends State<_EqualizerBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    if (widget.isPlaying) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant _EqualizerBars oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        _controller.repeat(reverse: true);
      } else {
        _controller.stop();
        _controller.value = 0.2;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        return SizedBox(
          width: widget.size * 1.1,
          height: widget.size,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _bar(
                (0.3 + 0.7 * (0.5 + 0.5 * sin(t * 3.14159 * 2))).clamp(
                  0.2,
                  1.0,
                ),
              ),
              _bar(
                (0.3 + 0.7 * (0.5 + 0.5 * sin((t + 0.33) * 3.14159 * 2))).clamp(
                  0.2,
                  1.0,
                ),
              ),
              _bar(
                (0.3 + 0.7 * (0.5 + 0.5 * sin((t + 0.66) * 3.14159 * 2))).clamp(
                  0.2,
                  1.0,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _bar(double fraction) {
    return Container(
      width: (widget.size * 1.1) / 4,
      height: widget.size * fraction,
      decoration: BoxDecoration(
        color: widget.color,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}
