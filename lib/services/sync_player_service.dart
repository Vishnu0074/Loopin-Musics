import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

import '../models/song.dart';
import '../models/sync_models.dart';
import 'audio_service.dart';
import 'monochrome_api.dart';
import 'app_storage.dart';

class SyncPlayerService {
  static final SyncPlayerService _instance = SyncPlayerService._internal();
  factory SyncPlayerService() => _instance;
  SyncPlayerService._internal() {
    _initLocalDevice();
    initializeMode();
  }

  static const int defaultPort = 4040;
  static const int discoveryPort = 4049;
  static const MethodChannel _networkChannel = MethodChannel('com.example.loopin/sync_network');
  bool _multicastLockHeld = false;

  Future<void> _setMulticastLock(bool enabled) async {
    if (!Platform.isAndroid || _multicastLockHeld == enabled) return;
    try {
      await _networkChannel.invokeMethod<void>(enabled ? 'acquireMulticastLock' : 'releaseMulticastLock');
      _multicastLockHeld = enabled;
    } catch (error) {
      debugPrint('Sync multicast lock ${enabled ? 'acquire' : 'release'} failed: $error');
    }
  }

  // Local device profile
  late SyncDevice _localDevice;
  SyncDevice get localDevice => _localDevice;

  // State controllers
  final _roleController = StreamController<SyncRole>.broadcast();
  final _groupController = StreamController<SyncGroup?>.broadcast();
  final _discoveredGroupsController =
      StreamController<List<DiscoveredGroup>>.broadcast();
  final _driftController = StreamController<int>.broadcast();
  final _localDeviceController = StreamController<SyncDevice>.broadcast();

  Stream<SyncRole> get roleStream => _roleController.stream;
  Stream<SyncGroup?> get groupStream => _groupController.stream;
  Stream<List<DiscoveredGroup>> get discoveredGroupsStream =>
      _discoveredGroupsController.stream;
  Stream<int> get driftStream => _driftController.stream;
  Stream<SyncDevice> get localDeviceStream => _localDeviceController.stream;

  SyncRole _role = SyncRole.idle;
  SyncRole get role => _role;

  SyncGroup? _group;
  SyncGroup? get group => _group;

  final Map<String, DiscoveredGroup> _discoveredGroups = {};
  List<DiscoveredGroup> get discoveredGroups =>
      List.unmodifiable(_discoveredGroups.values.toList());

  // Host state
  HttpServer? _hostServer;
  RawDatagramSocket? _hostUdpSocket;
  Timer? _hostBeaconTimer;
  Timer? _hostHeartbeatTimer;
  final Map<String, WebSocket> _clientSockets = {};
  final Map<String, SyncDevice> _memberDevices = {};

  // Client state
  WebSocket? _clientSocket;
  Completer<void>? _joinCompleter;
  Timer? _clientClockSyncTimer;
  Timer? _scheduledStartTimer;
  int _clockOffsetMs = 0; // host_time - local_time
  int _latencyMs = 0; // RTT
  int _currentDriftMs = 0;
  SyncConnectionStatus _connectionStatus = SyncConnectionStatus.idle;

  // Discovery state
  RawDatagramSocket? _discoverySocket;
  Timer? _discoveryPruneTimer;

  // Dedicated sync audio player (for synchronized local playback)
  AudioPlayer? _syncPlayer;
  String? _loadedTrackId;
  bool _standaloneMode = false;
  Future<void>? _modeLoadJob;
  bool _modeInitialized = false;
  final AppStorage _storage = AppStorage();
  static const String _standaloneStorageKey = 'loopin_standalone_mode';

  Future<void> initializeMode() async {
    if (_modeInitialized) return;
    if (_modeLoadJob != null) return _modeLoadJob;
    _modeLoadJob = () async {
      _standaloneMode = (await _storage.read(key: _standaloneStorageKey)) == 'true';
      _modeInitialized = true;
      if (!_standaloneMode) await _startDiscoveryListener();
    }();
    try {
      await _modeLoadJob;
    } finally {
      _modeLoadJob = null;
    }
  }

  Future<void> setStandaloneMode(bool enabled) async {
    await initializeMode();
    if (_standaloneMode == enabled) return;
    _standaloneMode = enabled;
    if (enabled) {
      // Standalone mode also exits any LAN Sync session and closes its sockets.
      await leaveGroup();
      _discoveryPruneTimer?.cancel();
      _discoveryPruneTimer = null;
      _discoverySocket?.close();
      _discoverySocket = null;
      await _setMulticastLock(false);
      _discoveredGroups.clear();
      _discoveredGroupsController.add(const []);
    } else {
      await _startDiscoveryListener();
    }
  }

  int get clockOffsetMs => _clockOffsetMs;
  int get latencyMs => _latencyMs;
  int get currentDriftMs => _currentDriftMs;
  SyncConnectionStatus get connectionStatus => _connectionStatus;

  void _initLocalDevice() {
    final randomId =
        '${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}-${Random().nextInt(10000)}';
    String platformName = 'Device';
    String host = 'Local';
    try {
      platformName = Platform.operatingSystem;
      host = Platform.localHostname.split('.').first;
    } catch (_) {}

    final capitalizedPlatform = platformName.isNotEmpty
        ? '${platformName[0].toUpperCase()}${platformName.substring(1)}'
        : 'Device';

    _localDevice = SyncDevice(
      id: randomId,
      name: '$capitalizedPlatform ($host)',
      platform: platformName,
      ipAddress: '127.0.0.1',
      isHost: false,
      joinedAt: DateTime.now(),
    );
  }

  Future<AudioPlayer> _ensurePlayer() async {
    _syncPlayer ??= AudioPlayer();
    return _syncPlayer!;
  }

  // ==========================================
  // DISCOVERY LISTENER (Background LAN Beacon)
  // ==========================================

  Future<void> _startDiscoveryListener() async {
    if (kIsWeb || _standaloneMode || _discoverySocket != null) return;
    try {
      await _setMulticastLock(true);
      _discoverySocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        discoveryPort,
        reuseAddress: true,
      );
      _discoverySocket?.broadcastEnabled = true;
      _discoverySocket?.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = _discoverySocket?.receive();
          if (datagram != null) {
            _handleDiscoveryDatagram(datagram);
          }
        }
      });

      _discoveryPruneTimer =
          Timer.periodic(const Duration(seconds: 4), (_) {
        final now = DateTime.now();
        final beforeCount = _discoveredGroups.length;
        _discoveredGroups.removeWhere(
            (key, val) => now.difference(val.lastSeen).inSeconds > 7);
        if (_discoveredGroups.length != beforeCount) {
          _discoveredGroupsController.add(discoveredGroups);
        }
      });
    } catch (e) {
      await _setMulticastLock(false);
      _discoverySocket?.close();
      _discoverySocket = null;
      debugPrint('SyncPlayerService discovery socket error: $e');
    }
  }

  void _handleDiscoveryDatagram(Datagram datagram) {
    try {
      final raw = utf8.decode(datagram.data);
      final json = jsonDecode(raw);
      if (json is! Map || json['app'] != 'loopin_sync') return;

      final code = json['code']?.toString() ?? '';
      if (code.isEmpty) return;

      // Ignore our own broadcast if we are hosting
      if (_role == SyncRole.host && _group?.code == code) return;

      // The UDP packet source is the interface that actually delivered the beacon.
      // The advertised address can belong to a VPN or mobile-data interface.
      final hostIp = datagram.address.address;
      final port = (json['port'] as num?)?.toInt() ?? defaultPort;
      final groupName = json['group_name']?.toString() ?? 'Sync Group';
      final hostName = json['host_name']?.toString() ?? 'Host Device';
      final membersCount = (json['members_count'] as num?)?.toInt() ?? 1;

      _discoveredGroups[code] = DiscoveredGroup(
        code: code,
        groupName: groupName,
        hostName: hostName,
        hostIp: hostIp,
        port: port,
        membersCount: membersCount,
        lastSeen: DateTime.now(),
      );

      _discoveredGroupsController.add(discoveredGroups);
    } catch (_) {}
  }

  // ==========================================
  // HOST ENGINE: CREATE & MANAGE GROUP
  // ==========================================

  Future<SyncGroup> createGroup({String? customGroupName}) async {
    await initializeMode();
    if (_standaloneMode) throw StateError('Disable Standalone mode to use Sync.');
    if (_role != SyncRole.idle) {
      await leaveGroup();
    }

    final code = _generateJoinCode();
    final groupName = customGroupName ?? 'Loopin Space ${code.substring(3)}';

    // Find host LAN IP
    String hostIp = '127.0.0.1';
    try {
      final interfaces = (await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      )).toList();
      interfaces.sort((a, b) {
        final aWifi = RegExp(r'wlan|wifi', caseSensitive: false).hasMatch(a.name);
        final bWifi = RegExp(r'wlan|wifi', caseSensitive: false).hasMatch(b.name);
        return (bWifi ? 1 : 0).compareTo(aWifi ? 1 : 0);
      });
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback && !addr.isLinkLocal) {
            hostIp = addr.address;
            break;
          }
        }
        if (hostIp != '127.0.0.1') break;
      }
    } catch (_) {}

    // Bind HTTP & WebSocket server
    int port = defaultPort;
    HttpServer? server;
    for (int p = defaultPort; p < defaultPort + 10; p++) {
      try {
        server = await HttpServer.bind(InternetAddress.anyIPv4, p);
        port = p;
        break;
      } catch (_) {}
    }

    if (server == null) {
      throw StateError('Could not bind Sync server. Ports are in use.');
    }
    _hostServer = server;

    _localDevice = _localDevice.copyWith(
      ipAddress: hostIp,
      isHost: true,
      status: SyncConnectionStatus.synced,
    );

    // Grab current track and queue from GlobalAudioService if available
    final globalAudio = GlobalAudioService();
    final curIdx = globalAudio.currentIndex;
    final curQueue = globalAudio.queue;
    Song? activeTrack;
    if (curIdx != null && curIdx >= 0 && curIdx < curQueue.length) {
      activeTrack = curQueue[curIdx];
    }

    _group = SyncGroup(
      code: code,
      name: groupName,
      hostId: _localDevice.id,
      hostName: _localDevice.name,
      hostIp: hostIp,
      port: port,
      members: [_localDevice],
      currentTrack: activeTrack,
      isPlaying: false,
      positionMs: 0,
      sharedQueue: curQueue,
      currentIndex: curIdx ?? 0,
    );

    _clientSockets.clear();
    _memberDevices.clear();
    _memberDevices[_localDevice.id] = _localDevice;

    _role = SyncRole.host;
    _roleController.add(_role);
    _groupController.add(_group);
    _localDeviceController.add(_localDevice);

    // Sync uses its own player. Pause the regular Loopin player so the host
    // does not produce a second, unsynchronized audio stream.
    await (await globalAudio.player).pause();

    // Listen for incoming WebSocket connections
    _hostServer!.listen((HttpRequest request) async {
      if (WebSocketTransformer.isUpgradeRequest(request)) {
        try {
          final socket = await WebSocketTransformer.upgrade(request);
          _handleHostIncomingClient(socket);
        } catch (e) {
          debugPrint('Host socket upgrade error: $e');
        }
      } else {
        request.response
          ..statusCode = HttpStatus.ok
          ..write('Loopin Sync Server active on port $port')
          ..close();
      }
    });

    // Start UDP discovery beacon
    _startHostBeacon(code, groupName, hostIp, port);

    // Start authoritative heartbeat
    _startHostHeartbeat();

    return _group!;
  }

  String _generateJoinCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rand = Random();
    final s = StringBuffer('LP-');
    for (int i = 0; i < 4; i++) {
      s.write(chars[rand.nextInt(chars.length)]);
    }
    return s.toString();
  }

  Future<void> _startHostBeacon(
    String code,
    String groupName,
    String hostIp,
    int port,
  ) async {
    try {
      _hostUdpSocket =
          await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      _hostUdpSocket?.broadcastEnabled = true;

      _hostBeaconTimer =
          Timer.periodic(const Duration(milliseconds: 1400), (_) {
        if (_role != SyncRole.host || _hostUdpSocket == null) return;
        final payload = jsonEncode({
          'app': 'loopin_sync',
          'code': code,
          'group_name': groupName,
          'host_name': _localDevice.name,
          'host_ip': hostIp,
          'port': port,
          'members_count': _group?.members.length ?? 1,
        });
        final bytes = utf8.encode(payload);
        try {
          _hostUdpSocket?.send(
            bytes,
            InternetAddress('255.255.255.255'),
            discoveryPort,
          );
        } catch (_) {}
      });
    } catch (e) {
      debugPrint('Sync host beacon error: $e');
    }
  }

  void _startHostHeartbeat() {
    _hostHeartbeatTimer =
        Timer.periodic(const Duration(milliseconds: 2000), (_) async {
      if (_role != SyncRole.host || _group == null) return;

      final player = await _ensurePlayer();
      final isPlaying = player.playing;
      final posMs = player.position.inMilliseconds;

      _group = _group!.copyWith(
        isPlaying: isPlaying,
        positionMs: posMs,
        serverTimeMs: DateTime.now().millisecondsSinceEpoch,
      );
      _groupController.add(_group);

      if (isPlaying) {
        _broadcastToFollowers({
          'type': 'heartbeat',
          'server_time_ms': DateTime.now().millisecondsSinceEpoch,
          'position_ms': posMs,
          'playing': isPlaying,
          'track_id': _group!.currentTrack?.id,
          'queue_index': _group!.currentIndex,
        });
      }
    });
  }

  void _handleHostIncomingClient(WebSocket socket) {
    String? clientId;
    socket.listen(
      (data) {
        try {
          final decoded = jsonDecode(data as String);
          if (decoded is! Map) return;
          final type = decoded['type']?.toString();

          switch (type) {
            case 'join':
              final requestedCode = decoded['code']?.toString().toUpperCase();
              if (_group == null || requestedCode != _group!.code) {
                socket.add(jsonEncode({
                  'type': 'join_rejected',
                  'reason': 'Invalid or expired Sync code.',
                }));
                unawaited(socket.close().then<void>((_) {}));
                return;
              }
              clientId = decoded['device_id']?.toString();
              if (clientId == null || clientId!.isEmpty) {
                unawaited(socket.close().then<void>((_) {}));
                return;
              }
              if (_clientSockets.containsKey(clientId!)) {
                socket.add(jsonEncode({
                  'type': 'join_rejected',
                  'reason': 'This device is already connected to the Sync group.',
                }));
                unawaited(socket.close().then<void>((_) {}));
                clientId = null;
                return;
              }
              final clientName =
                  decoded['device_name']?.toString() ?? 'Follower';
              final platform =
                  decoded['platform']?.toString() ?? 'device';

              final newDevice = SyncDevice(
                id: clientId!,
                name: clientName,
                platform: platform,
                ipAddress: '',
                isHost: false,
                status: SyncConnectionStatus.syncing,
                joinedAt: DateTime.now(),
              );

              _clientSockets[clientId!] = socket;
              _memberDevices[clientId!] = newDevice;

              _group = _group!.copyWith(
                members: _memberDevices.values.toList(),
              );
              _groupController.add(_group);

              // Send welcome state to newly joined client
              socket.add(jsonEncode({
                'type': 'welcome',
                'group': _group!.toJson(),
                'host_time': DateTime.now().millisecondsSinceEpoch,
              }));

              // Notify existing members
              _broadcastMembersUpdate();
              break;

            case 'clock_sync_ping':
              if (clientId == null || !_clientSockets.containsKey(clientId)) return;
              final t1 = (decoded['t1'] as num?)?.toInt() ?? 0;
              final t2 = DateTime.now().millisecondsSinceEpoch;
              socket.add(jsonEncode({
                'type': 'clock_sync_pong',
                't1': t1,
                't2': t2,
                't3': DateTime.now().millisecondsSinceEpoch,
              }));
              break;

            case 'device_telemetry':
              if (clientId == null || !_clientSockets.containsKey(clientId)) return;
              final devId = decoded['device_id']?.toString();
              if (devId != null && _memberDevices.containsKey(devId)) {
                final dev = _memberDevices[devId]!;
                _memberDevices[devId] = dev.copyWith(
                  latencyMs: (decoded['latency_ms'] as num?)?.toInt() ?? 0,
                  clockOffsetMs:
                      (decoded['clock_offset_ms'] as num?)?.toInt() ?? 0,
                  driftMs: (decoded['drift_ms'] as num?)?.toInt() ?? 0,
                  status: SyncConnectionStatus.values.firstWhere(
                    (s) => s.name == decoded['status'],
                    orElse: () => SyncConnectionStatus.synced,
                  ),
                );
                _group = _group!.copyWith(
                  members: _memberDevices.values.toList(),
                );
                _groupController.add(_group);
              }
              break;

            case 'leave':
              if (clientId == null || !_clientSockets.containsKey(clientId)) return;
              if (clientId != null) {
                _removeClient(clientId!);
              }
              break;
          }
        } catch (e) {
          debugPrint('Host message processing error: $e');
        }
      },
      onDone: () {
        if (clientId != null) _removeClient(clientId!);
      },
      onError: (err) {
        if (clientId != null) _removeClient(clientId!);
      },
    );
  }

  void _removeClient(String clientId) {
    final socket = _clientSockets.remove(clientId);
    final removed = _memberDevices.remove(clientId);
    if (socket == null && removed == null) return;
    if (socket != null) unawaited(socket.close().then<void>((_) {}));
    if (_group != null) {
      _group = _group!.copyWith(members: _memberDevices.values.toList());
      _groupController.add(_group);
      _broadcastMembersUpdate();
    }
  }

  void _broadcastMembersUpdate() {
    if (_group == null) return;
    _broadcastToFollowers({
      'type': 'members_update',
      'members': _group!.members.map((m) => m.toJson()).toList(),
    });
  }

  void _broadcastToFollowers(Map<String, dynamic> message) {
    final payload = jsonEncode(message);
    for (final socket in _clientSockets.values) {
      try {
        socket.add(payload);
      } catch (_) {}
    }
  }

  // ==========================================
  // HOST CONTROLS: KICK DEVICE & DISBAND
  // ==========================================

  void kickDevice(String deviceId) {
    if (_role != SyncRole.host || deviceId == _localDevice.id) return;
    final socket = _clientSockets[deviceId];
    if (socket != null) {
      try {
        socket.add(jsonEncode({
          'type': 'kicked',
          'reason': 'You were removed from the sync group by the host.',
        }));
      } catch (_) {}
    }
    _removeClient(deviceId);
  }

  Future<void> disbandGroup() async {
    if (_role != SyncRole.host) return;

    _broadcastToFollowers({
      'type': 'group_disbanded',
      'reason': 'The host disbanded this sync group.',
    });

    for (final s in _clientSockets.values) {
      try {
        await s.close();
      } catch (_) {}
    }
    _clientSockets.clear();
    _memberDevices.clear();

    _scheduledStartTimer?.cancel();
    _scheduledStartTimer = null;
    if (_syncPlayer != null) {
      try { await _syncPlayer!.stop(); } catch (_) {}
    }
    _loadedTrackId = null;

    _hostBeaconTimer?.cancel();
    _hostHeartbeatTimer?.cancel();
    _hostUdpSocket?.close();
    await _hostServer?.close(force: true);

    _hostServer = null;
    _hostUdpSocket = null;
    _hostBeaconTimer = null;
    _hostHeartbeatTimer = null;

    _group = null;
    _role = SyncRole.idle;

    _roleController.add(_role);
    _groupController.add(_group);
  }

  // ==========================================
  // CLIENT ENGINE: JOIN GROUP & SYNC PROTOCOL
  // ==========================================

  Future<void> joinGroup(String codeOrAddress) async {
    await initializeMode();
    if (_standaloneMode) throw StateError('Disable Standalone mode to use Sync.');
    if (_role != SyncRole.idle) {
      await leaveGroup();
    }

    String targetIp = '';
    int targetPort = defaultPort;

    final trimmed = codeOrAddress.trim().toUpperCase();

    // Check if code was discovered via UDP
    if (_discoveredGroups.containsKey(trimmed)) {
      final disc = _discoveredGroups[trimmed]!;
      targetIp = disc.hostIp;
      targetPort = disc.port;
    } else {
      // Check if user entered direct IP or IP:port
      if (trimmed.contains('.')) {
        if (trimmed.contains(':')) {
          final parts = trimmed.split(':');
          targetIp = parts[0];
          targetPort = int.tryParse(parts[1]) ?? defaultPort;
        } else {
          targetIp = trimmed;
          targetPort = defaultPort;
        }
      } else {
        // Try to match partial code against discovered groups
        DiscoveredGroup? match;
        for (final g in _discoveredGroups.values) {
          if (g.code.toUpperCase() == trimmed || g.code.endsWith(trimmed)) {
            match = g;
            break;
          }
        }
        if (match != null) {
          targetIp = match.hostIp;
          targetPort = match.port;
        }
      }
    }

    if (targetIp.isEmpty) {
      throw ArgumentError(
        'Could not locate sync group "$codeOrAddress". Make sure you are on the same Wi-Fi network.',
      );
    }

    _connectionStatus = SyncConnectionStatus.connecting;
    _localDevice = _localDevice.copyWith(
      status: _connectionStatus,
      isHost: false,
    );
    _localDeviceController.add(_localDevice);

    try {
      String? discoveredCode = _discoveredGroups[trimmed]?.code;
      if (discoveredCode == null) {
        for (final discovered in _discoveredGroups.values) {
          if (discovered.hostIp == targetIp && discovered.port == targetPort) {
            discoveredCode = discovered.code;
            break;
          }
        }
      }
      if (discoveredCode == null) {
        throw ArgumentError('Join this Sync group using its discovered join code.');
      }
      final wsUri = Uri.parse('ws://$targetIp:$targetPort/sync');
      final socket = await WebSocket.connect(wsUri.toString()).timeout(
        const Duration(seconds: 6),
      );
      _clientSocket = socket;
      _role = SyncRole.client;
      _joinCompleter = Completer<void>();
      _roleController.add(_role);

      // Send handshake
      socket.add(jsonEncode({
        'type': 'join',
        'code': discoveredCode,
        'device_id': _localDevice.id,
        'device_name': _localDevice.name,
        'platform': _localDevice.platform,
      }));

      // Listen for host commands
      socket.listen(
        _handleClientIncomingMessage,
        onDone: _handleClientDisconnected,
        onError: (err) => _handleClientDisconnected(),
        cancelOnError: false,
      );

      // Wait until the host accepts the code and sends the initial group state.
      await _joinCompleter!.future.timeout(const Duration(seconds: 6));
      _joinCompleter = null;

      // Do not let the normal Loopin player overlap this device's Sync stream.
      await (await GlobalAudioService().player).pause();

      // Perform NTP Clock Synchronization Burst before restoring the host
      // snapshot so the recipient can compensate for clock offset immediately.
      await _runClockSyncBurst();
      await _restoreWelcomePlayback();

      // Start periodic ongoing clock synchronization (every 3.5s)
      _clientClockSyncTimer = Timer.periodic(
        const Duration(milliseconds: 3500),
        (_) => _sendClockSyncPing(),
      );
    } catch (e) {
      _joinCompleter = null;
      _clientClockSyncTimer?.cancel();
      _clientClockSyncTimer = null;
      _pendingPings.clear();
      final failedSocket = _clientSocket;
      _clientSocket = null;
      if (failedSocket != null) {
        try { await failedSocket.close(); } catch (_) {}
      }
      _group = null;
      _groupController.add(null);
      _connectionStatus = SyncConnectionStatus.disconnected;
      _role = SyncRole.idle;
      _roleController.add(_role);
      _localDevice = _localDevice.copyWith(status: _connectionStatus);
      _localDeviceController.add(_localDevice);
      rethrow;
    }
  }

  void _handleClientIncomingMessage(dynamic raw) {
    try {
      final decoded = jsonDecode(raw as String);
      if (decoded is! Map) return;
      final type = decoded['type']?.toString();

      switch (type) {
        case 'join_rejected':
          final reason = decoded['reason']?.toString() ?? 'Sync group rejected the connection.';
          final completer = _joinCompleter;
          if (completer != null && !completer.isCompleted) {
            completer.completeError(StateError(reason));
          } else {
            unawaited(leaveGroup());
          }
          debugPrint('Sync join rejected: $reason');
          break;

        case 'welcome':
          if (decoded['group'] != null) {
            _group = SyncGroup.fromJson(
              Map<String, dynamic>.from(decoded['group'] as Map),
            );
            _groupController.add(_group);
            final completer = _joinCompleter;
            if (completer != null && !completer.isCompleted) {
              completer.complete();
            }
          }
          break;

        case 'members_update':
          if (decoded['members'] is List && _group != null) {
            final membersList = (decoded['members'] as List)
                .map((m) =>
                    SyncDevice.fromJson(Map<String, dynamic>.from(m as Map)))
                .toList();
            _group = _group!.copyWith(members: membersList);
            _groupController.add(_group);
          }
          break;

        case 'clock_sync_pong':
          _handleClockSyncPong(decoded);
          break;

        case 'schedule_play':
          _handleSchedulePlay(decoded);
          break;

        case 'schedule_seek':
          _handleScheduleSeek(decoded);
          break;

        case 'pause':
          _handleHostPause(decoded);
          break;

        case 'queue_update':
          _handleQueueUpdate(decoded);
          break;

        case 'heartbeat':
          _handleHostHeartbeat(decoded);
          break;

        case 'kicked':
          final reason =
              decoded['reason']?.toString() ?? 'Removed by host';
          debugPrint('Sync kicked: $reason');
          leaveGroup();
          break;

        case 'group_disbanded':
          leaveGroup();
          break;
      }
    } catch (e) {
      debugPrint('Client sync message handling error: $e');
    }
  }

  /// Loads the current host track from the welcome snapshot. A client may
  /// join after the host has already started playback; without this catch-up
  /// step it waits forever for a future schedule_play message.
  Future<void> _restoreWelcomePlayback() async {
    if (_role != SyncRole.client || _group == null) return;
    final group = _group!;
    final song = group.currentTrack;
    if (song == null) return;

    try {
      final player = await _ensurePlayer();
      await _prepareTrackOnPlayer(player, song);

      final now = DateTime.now().millisecondsSinceEpoch;
      final hostNow = now + _clockOffsetMs;
      final elapsed = group.serverTimeMs > 0
          ? (hostNow - group.serverTimeMs).clamp(0, 10000)
          : 0;
      final expectedPosition = group.positionMs +
          (group.isPlaying ? elapsed : 0);

      if (!group.isPlaying) {
        _scheduledStartTimer?.cancel();
        await player.pause();
        await player.seek(Duration(milliseconds: expectedPosition));
        _connectionStatus = SyncConnectionStatus.synced;
        _localDevice = _localDevice.copyWith(status: _connectionStatus);
        _localDeviceController.add(_localDevice);
        return;
      }

      await _handleSchedulePlay({
        'track': song.toJson(),
        'position_ms': expectedPosition,
        'target_epoch_ms': now + 650 + _clockOffsetMs,
        'queue_index': group.currentIndex,
      });
    } catch (error, stack) {
      debugPrint('Sync welcome playback restore failed: $error');
      debugPrintStack(stackTrace: stack);
      _connectionStatus = SyncConnectionStatus.disconnected;
      _localDevice = _localDevice.copyWith(status: _connectionStatus);
      _localDeviceController.add(_localDevice);
    }
  }

  void _handleClientDisconnected() {
    if (_role == SyncRole.client) {
      leaveGroup();
    }
  }

  Future<void> leaveGroup() async {
    _clientClockSyncTimer?.cancel();
    _scheduledStartTimer?.cancel();
    _clientClockSyncTimer = null;
    _pendingPings.clear();
    _scheduledStartTimer = null;

    if (_role == SyncRole.host) {
      await disbandGroup();
      return;
    }

    if (_role == SyncRole.client && _clientSocket != null) {
      try {
        _clientSocket!.add(jsonEncode({
          'type': 'leave',
          'device_id': _localDevice.id,
        }));
        await _clientSocket!.close();
      } catch (_) {}
      _clientSocket = null;
    }

    // Stop sync player
    if (_syncPlayer != null) {
      try {
        await _syncPlayer!.stop();
      } catch (_) {}
    }
    _loadedTrackId = null;

    _role = SyncRole.idle;
    _group = null;
    _clockOffsetMs = 0;
    _latencyMs = 0;
    _currentDriftMs = 0;
    _connectionStatus = SyncConnectionStatus.idle;

    _localDevice = _localDevice.copyWith(
      isHost: false,
      status: _connectionStatus,
      latencyMs: 0,
      clockOffsetMs: 0,
      driftMs: 0,
    );

    _roleController.add(_role);
    _groupController.add(_group);
    _localDeviceController.add(_localDevice);
    _driftController.add(0);
  }

  // ==========================================
  // CLOCK SYNCHRONIZATION ENGINE (NTP / CRISTIAN)
  // ==========================================

  final Map<int, int> _pendingPings = {};

  Future<void> _runClockSyncBurst() async {
    // Send 8 pings spaced 80ms apart to quickly converge on an accurate clock offset
    for (int i = 0; i < 8; i++) {
      if (_role != SyncRole.client || _clientSocket == null) break;
      _sendClockSyncPing();
      await Future.delayed(const Duration(milliseconds: 80));
    }
  }

  void _sendClockSyncPing() {
    if (_clientSocket == null) return;
    final t1 = DateTime.now().millisecondsSinceEpoch;
    _pendingPings[t1] = t1;
    try {
      _clientSocket!.add(jsonEncode({
        'type': 'clock_sync_ping',
        't1': t1,
      }));
    } catch (_) {}
  }

  void _handleClockSyncPong(Map<dynamic, dynamic> data) {
    final t4 = DateTime.now().millisecondsSinceEpoch;
    final t1 = (data['t1'] as num?)?.toInt() ?? 0;
    final t2 = (data['t2'] as num?)?.toInt() ?? 0;
    final t3 = (data['t3'] as num?)?.toInt() ?? 0;

    _pendingPings.remove(t1);

    if (t1 <= 0 || t2 <= 0 || t3 <= 0 || t4 < t1) return;

    // Standard NTP / Cristian's Formula
    final rtt = (t4 - t1) - (t3 - t2);
    final offset = (((t2 - t1) + (t3 - t4)) / 2).round();

    _latencyMs = rtt.clamp(0, 5000);

    if (_clockOffsetMs == 0) {
      _clockOffsetMs = offset;
    } else {
      // Exponential Moving Average (EMA) to smoothly track clock skew without jitter
      _clockOffsetMs = (_clockOffsetMs * 0.75 + offset * 0.25).round();
    }

    _connectionStatus = SyncConnectionStatus.synced;
    _localDevice = _localDevice.copyWith(
      latencyMs: _latencyMs,
      clockOffsetMs: _clockOffsetMs,
      status: _connectionStatus,
    );
    _localDeviceController.add(_localDevice);

    _sendDeviceTelemetry();
  }

  void _sendDeviceTelemetry() {
    if (_clientSocket == null || _role != SyncRole.client) return;
    try {
      _clientSocket!.add(jsonEncode({
        'type': 'device_telemetry',
        'device_id': _localDevice.id,
        'latency_ms': _latencyMs,
        'clock_offset_ms': _clockOffsetMs,
        'drift_ms': _currentDriftMs,
        'status': _connectionStatus.name,
      }));
    } catch (_) {}
  }

  // ==========================================
  // SCHEDULED PLAYBACK & PRE-BUFFERING ENGINE
  // ==========================================

  Future<void> _handleSchedulePlay(Map<dynamic, dynamic> data) async {
    final targetEpochMs = (data['target_epoch_ms'] as num?)?.toInt() ?? 0;
    final positionMs = (data['position_ms'] as num?)?.toInt() ?? 0;
    final trackData = data['track'];
    final queueIndex = (data['queue_index'] as num?)?.toInt() ?? 0;

    if (trackData is Map) {
      final song = Song.fromJson(Map<String, dynamic>.from(trackData));
      final player = await _ensurePlayer();

      // Load successfully before publishing the new active track.
      await _prepareTrackOnPlayer(player, song);
      _group = _group?.copyWith(
        currentTrack: song,
        isPlaying: true,
        positionMs: positionMs,
        currentIndex: queueIndex,
      );
      _groupController.add(_group);

      // Seek to target position while paused (pre-buffer)
      if (positionMs > 0) {
        await player.seek(Duration(milliseconds: positionMs));
      }
      await player.setSpeed(1.0);

      // Calculate scheduled wall-clock trigger time
      // local_target = target_epoch_ms - clock_offset
      final localTargetEpochMs = targetEpochMs - _clockOffsetMs;
      final now = DateTime.now().millisecondsSinceEpoch;
      final delayMs = localTargetEpochMs - now;

      _scheduledStartTimer?.cancel();

      if (delayMs > 0) {
        _scheduledStartTimer = Timer(Duration(milliseconds: delayMs), () async {
          await player.play();
          _connectionStatus = SyncConnectionStatus.synced;
          _localDevice = _localDevice.copyWith(status: _connectionStatus);
          _localDeviceController.add(_localDevice);
        });
      } else {
        // Late arrival: seek ahead to compensate for lost time and start immediately
        final catchUpMs = positionMs + (-delayMs);
        await player.seek(Duration(milliseconds: catchUpMs));
        await player.play();
      }
    }
  }

  Future<void> _handleScheduleSeek(Map<dynamic, dynamic> data) async {
    final targetEpochMs = (data['target_epoch_ms'] as num?)?.toInt() ?? 0;
    final positionMs = (data['position_ms'] as num?)?.toInt() ?? 0;

    final player = await _ensurePlayer();
    await player.seek(Duration(milliseconds: positionMs));
    await player.setSpeed(1.0);

    final localTargetEpochMs = targetEpochMs - _clockOffsetMs;
    final now = DateTime.now().millisecondsSinceEpoch;
    final delayMs = localTargetEpochMs - now;

    _scheduledStartTimer?.cancel();
    if (delayMs > 0) {
      _scheduledStartTimer = Timer(Duration(milliseconds: delayMs), () async {
        await player.play();
      });
    } else {
      await player.play();
    }
  }

  Future<void> _handleHostPause(Map<dynamic, dynamic> data) async {
    _scheduledStartTimer?.cancel();
    final posMs = (data['position_ms'] as num?)?.toInt();
    final player = await _ensurePlayer();
    await player.pause();
    if (posMs != null) {
      await player.seek(Duration(milliseconds: posMs));
    }
    _group = _group?.copyWith(isPlaying: false, positionMs: posMs ?? _group!.positionMs);
    _groupController.add(_group);
  }

  Future<void> _handleQueueUpdate(Map<dynamic, dynamic> data) async {
    if (data['queue'] is List) {
      final songs = (data['queue'] as List)
          .map((s) => Song.fromJson(Map<String, dynamic>.from(s as Map)))
          .toList();
      final idx = (data['current_index'] as num?)?.toInt() ?? 0;
      _group = _group?.copyWith(sharedQueue: songs, currentIndex: idx);
      _groupController.add(_group);
    }
  }

  Future<void> _prepareTrackOnPlayer(AudioPlayer player, Song song) async {
    // Reusing the loaded source is essential when resuming: calling setUrl()
    // again resets the playhead and makes a pause/resume behave like a restart.
    if (_loadedTrackId == song.id && player.audioSource != null) return;

    final suppliedUrl = song.mediaUrl.trim();
    if (suppliedUrl.isNotEmpty) {
      try {
        // A URL shared by the host can be short-lived. Try it first, but never
        // leave the recipient stuck on an expired provider URL.
        await player.setUrl(suppliedUrl).timeout(const Duration(seconds: 12));
        _loadedTrackId = song.id;
        return;
      } catch (error) {
        debugPrint('Sync shared stream URL failed; resolving a fresh URL: $error');
      }
    }

    final resolved = await MonochromeApi().resolveStream(song);
    final playableUrl = resolved?.trim() ?? '';
    if (playableUrl.isEmpty) {
      throw StateError('Could not resolve an audio stream for ${song.title}.');
    }

    await player.setUrl(playableUrl).timeout(const Duration(seconds: 15));
    _loadedTrackId = song.id;
  }

  // ==========================================
  // DRIFT CORRECTION ENGINE (MULTI-TIER STEERING)
  // ==========================================

  Future<void> _handleHostHeartbeat(Map<dynamic, dynamic> data) async {
    if (_role != SyncRole.client) return;

    final serverTimeMs = (data['server_time_ms'] as num?)?.toInt() ?? 0;
    final serverPosMs = (data['position_ms'] as num?)?.toInt() ?? 0;
    final isHostPlaying = data['playing'] == true;

    final player = await _ensurePlayer();

    // 1. Estimate host time right now
    final nowHost = DateTime.now().millisecondsSinceEpoch + _clockOffsetMs;
    final transitAgeMs = (nowHost - serverTimeMs).clamp(0, 10000);

    // 2. Expected authoritative host playback position
    final expectedPosMs =
        serverPosMs + (isHostPlaying ? transitAgeMs : 0);

    // 3. Follower's actual local playback position
    final actualPosMs = player.position.inMilliseconds;

    // 4. Drift calculation: positive = follower ahead, negative = follower behind
    final driftMs = actualPosMs - expectedPosMs;
    _currentDriftMs = driftMs;
    _driftController.add(driftMs);

    // Sync play/pause state if mismatched
    if (isHostPlaying && !player.playing) {
      await player.seek(Duration(milliseconds: expectedPosMs));
      await player.play();
    } else if (!isHostPlaying && player.playing) {
      await player.pause();
      return;
    }

    // 5. Four-Tier Drift Steering
    final absDrift = driftMs.abs();

    if (absDrift <= 25) {
      // Tier 1: Perceptually in phase (< 25ms). Keep native 1.0x speed.
      _connectionStatus = SyncConnectionStatus.synced;
      if (player.speed != 1.0) {
        await player.setSpeed(1.0);
      }
    } else if (absDrift <= 320) {
      // Tier 2: Minor drift (25ms - 320ms).
      // Smooth pitch-preserved tempo micro-adjustment. NO POP, NO JUMP!
      _connectionStatus = SyncConnectionStatus.adjusting;
      if (driftMs < 0) {
        // Follower is lagging behind host: speed up to 1.04x
        await player.setSpeed(1.04);
      } else {
        // Follower is ahead of host: slow down to 0.96x
        await player.setSpeed(0.96);
      }
    } else if (absDrift <= 2000) {
      // Tier 3: Medium drift (320ms - 2000ms).
      // Micro-seek ahead with 40ms buffer compensation.
      _connectionStatus = SyncConnectionStatus.adjusting;
      await player.seek(Duration(milliseconds: expectedPosMs + 40));
      await player.setSpeed(1.0);
    } else {
      // Tier 4: Major drift (> 2000ms). Hard seek to authoritative position.
      _connectionStatus = SyncConnectionStatus.syncing;
      await player.seek(Duration(milliseconds: expectedPosMs));
      await player.setSpeed(1.0);
    }

    _localDevice = _localDevice.copyWith(
      driftMs: _currentDriftMs,
      status: _connectionStatus,
    );
    _localDeviceController.add(_localDevice);

    // Report telemetry back to host
    _sendDeviceTelemetry();
  }

  // ==========================================
  // HOST SHARED PLAYBACK & QUEUE CONTROLS
  // ==========================================

  Future<void> hostSchedulePlay({
    Song? song,
    int? positionMs,
    int leadTimeMs = 750,
  }) async {
    if (_role != SyncRole.host || _group == null) return;

    final targetSong = song ?? _group!.currentTrack;
    if (targetSong == null) return;

    final player = await _ensurePlayer();
    await _prepareTrackOnPlayer(player, targetSong);

    final startPos = positionMs ?? player.position.inMilliseconds;
    if (startPos > 0) {
      await player.seek(Duration(milliseconds: startPos));
    }
    await player.setSpeed(1.0);

    final nowHost = DateTime.now().millisecondsSinceEpoch;
    final targetEpochMs = nowHost + leadTimeMs;

    _group = _group!.copyWith(
      currentTrack: targetSong,
      isPlaying: true,
      positionMs: startPos,
    );
    _groupController.add(_group);

    // Broadcast scheduled start to all followers
    _broadcastToFollowers({
      'type': 'schedule_play',
      'target_epoch_ms': targetEpochMs,
      'position_ms': startPos,
      'track': targetSong.toJson(),
      'queue_index': _group!.currentIndex,
      'host_time': nowHost,
    });

    // Schedule host's own local start
    _scheduledStartTimer?.cancel();
    _scheduledStartTimer =
        Timer(Duration(milliseconds: leadTimeMs), () async {
      await player.play();
    });
  }

  Future<void> hostPause() async {
    if (_role != SyncRole.host || _group == null) return;

    final player = await _ensurePlayer();
    _scheduledStartTimer?.cancel();
    await player.pause();

    final posMs = player.position.inMilliseconds;
    _group = _group!.copyWith(isPlaying: false, positionMs: posMs);
    _groupController.add(_group);

    _broadcastToFollowers({
      'type': 'pause',
      'position_ms': posMs,
    });
  }

  Future<void> hostSeek(Duration position, {int leadTimeMs = 600}) async {
    if (_role != SyncRole.host || _group == null) return;

    final player = await _ensurePlayer();
    _scheduledStartTimer?.cancel();
    final posMs = position.inMilliseconds;
    await player.seek(position);

    final nowHost = DateTime.now().millisecondsSinceEpoch;
    final targetEpochMs = nowHost + leadTimeMs;

    _broadcastToFollowers({
      'type': 'schedule_seek',
      'target_epoch_ms': targetEpochMs,
      'position_ms': posMs,
    });

    if (player.playing) {
      _scheduledStartTimer =
          Timer(Duration(milliseconds: leadTimeMs), () async {
        await player.play();
      });
    }
  }

  Future<void> hostNextTrack() async {
    if (_role != SyncRole.host || _group == null) return;
    final q = _group!.sharedQueue;
    if (q.isEmpty) return;
    final nextIdx = (_group!.currentIndex + 1) % q.length;
    _group = _group!.copyWith(currentIndex: nextIdx);
    await hostSchedulePlay(song: q[nextIdx], positionMs: 0);
  }

  Future<void> hostPreviousTrack() async {
    if (_role != SyncRole.host || _group == null) return;
    final q = _group!.sharedQueue;
    if (q.isEmpty) return;
    final prevIdx =
        (_group!.currentIndex - 1 + q.length) % q.length;
    _group = _group!.copyWith(currentIndex: prevIdx);
    await hostSchedulePlay(song: q[prevIdx], positionMs: 0);
  }

  void hostUpdateQueue(List<Song> songs, {int? newIndex}) {
    if (_role != SyncRole.host || _group == null) return;
    _group = _group!.copyWith(
      sharedQueue: songs,
      currentIndex: newIndex ?? _group!.currentIndex,
    );
    _groupController.add(_group);
    _broadcastToFollowers({
      'type': 'queue_update',
      'queue': songs.map((s) => s.toJson()).toList(),
      'current_index': _group!.currentIndex,
    });
  }

  void hostRemoveFromQueue(int index) {
    if (_role != SyncRole.host || _group == null) return;
    final q = List<Song>.from(_group!.sharedQueue);
    if (index >= 0 && index < q.length) {
      q.removeAt(index);
      int curIdx = _group!.currentIndex;
      if (curIdx >= q.length) curIdx = max(0, q.length - 1);
      hostUpdateQueue(q, newIndex: curIdx);
    }
  }

  Future<void> setLocalVolume(double volume) async {
    final player = await _ensurePlayer();
    await player.setVolume(volume.clamp(0.0, 1.0));
  }

  void dispose() {
    _discoverySocket?.close();
    _discoveryPruneTimer?.cancel();
    unawaited(_setMulticastLock(false));
    _hostBeaconTimer?.cancel();
    _hostHeartbeatTimer?.cancel();
    _clientClockSyncTimer?.cancel();
    _scheduledStartTimer?.cancel();
    _syncPlayer?.dispose();
    _syncPlayer = null;
    _loadedTrackId = null;
    _roleController.close();
    _groupController.close();
    _discoveredGroupsController.close();
    _driftController.close();
    _localDeviceController.close();
  }
}
