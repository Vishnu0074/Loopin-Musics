import 'song.dart';

enum SyncRole {
  idle,
  host,
  client,
}

enum SyncConnectionStatus {
  idle,
  connecting,
  synced,
  adjusting,
  syncing,
  disconnected,
}

enum SyncQuality {
  excellent,
  good,
  fair,
  poor,
}

class SyncDevice {
  final String id;
  final String name;
  final String platform;
  final String ipAddress;
  final bool isHost;
  final int latencyMs;
  final int clockOffsetMs;
  final int driftMs;
  final SyncConnectionStatus status;
  final DateTime joinedAt;

  const SyncDevice({
    required this.id,
    required this.name,
    required this.platform,
    required this.ipAddress,
    this.isHost = false,
    this.latencyMs = 0,
    this.clockOffsetMs = 0,
    this.driftMs = 0,
    this.status = SyncConnectionStatus.idle,
    required this.joinedAt,
  });

  SyncQuality get quality {
    if (latencyMs <= 35) return SyncQuality.excellent;
    if (latencyMs <= 80) return SyncQuality.good;
    if (latencyMs <= 150) return SyncQuality.fair;
    return SyncQuality.poor;
  }

  SyncDevice copyWith({
    String? id,
    String? name,
    String? platform,
    String? ipAddress,
    bool? isHost,
    int? latencyMs,
    int? clockOffsetMs,
    int? driftMs,
    SyncConnectionStatus? status,
    DateTime? joinedAt,
  }) {
    return SyncDevice(
      id: id ?? this.id,
      name: name ?? this.name,
      platform: platform ?? this.platform,
      ipAddress: ipAddress ?? this.ipAddress,
      isHost: isHost ?? this.isHost,
      latencyMs: latencyMs ?? this.latencyMs,
      clockOffsetMs: clockOffsetMs ?? this.clockOffsetMs,
      driftMs: driftMs ?? this.driftMs,
      status: status ?? this.status,
      joinedAt: joinedAt ?? this.joinedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'platform': platform,
    'ip_address': ipAddress,
    'is_host': isHost,
    'latency_ms': latencyMs,
    'clock_offset_ms': clockOffsetMs,
    'drift_ms': driftMs,
    'status': status.name,
    'joined_at': joinedAt.toIso8601String(),
  };

  factory SyncDevice.fromJson(Map<String, dynamic> json) => SyncDevice(
    id: json['id']?.toString() ?? '',
    name: json['name']?.toString() ?? 'Device',
    platform: json['platform']?.toString() ?? 'unknown',
    ipAddress: json['ip_address']?.toString() ?? '',
    isHost: json['is_host'] == true,
    latencyMs: (json['latency_ms'] as num?)?.toInt() ?? 0,
    clockOffsetMs: (json['clock_offset_ms'] as num?)?.toInt() ?? 0,
    driftMs: (json['drift_ms'] as num?)?.toInt() ?? 0,
    status: SyncConnectionStatus.values.firstWhere(
      (s) => s.name == json['status'],
      orElse: () => SyncConnectionStatus.idle,
    ),
    joinedAt: json['joined_at'] != null
        ? DateTime.tryParse(json['joined_at'].toString()) ?? DateTime.now()
        : DateTime.now(),
  );
}

class DiscoveredGroup {
  final String code;
  final String groupName;
  final String hostName;
  final String hostIp;
  final int port;
  final int membersCount;
  final DateTime lastSeen;

  const DiscoveredGroup({
    required this.code,
    required this.groupName,
    required this.hostName,
    required this.hostIp,
    required this.port,
    required this.membersCount,
    required this.lastSeen,
  });

  DiscoveredGroup copyWith({
    String? code,
    String? groupName,
    String? hostName,
    String? hostIp,
    int? port,
    int? membersCount,
    DateTime? lastSeen,
  }) {
    return DiscoveredGroup(
      code: code ?? this.code,
      groupName: groupName ?? this.groupName,
      hostName: hostName ?? this.hostName,
      hostIp: hostIp ?? this.hostIp,
      port: port ?? this.port,
      membersCount: membersCount ?? this.membersCount,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }
}

class SyncGroup {
  final String code;
  final String name;
  final String hostId;
  final String hostName;
  final String hostIp;
  final int port;
  final List<SyncDevice> members;
  final Song? currentTrack;
  final bool isPlaying;
  final int positionMs;
  final int serverTimeMs;
  final List<Song> sharedQueue;
  final int currentIndex;

  const SyncGroup({
    required this.code,
    required this.name,
    required this.hostId,
    required this.hostName,
    required this.hostIp,
    required this.port,
    this.members = const [],
    this.currentTrack,
    this.isPlaying = false,
    this.positionMs = 0,
    this.serverTimeMs = 0,
    this.sharedQueue = const [],
    this.currentIndex = 0,
  });

  SyncGroup copyWith({
    String? code,
    String? name,
    String? hostId,
    String? hostName,
    String? hostIp,
    int? port,
    List<SyncDevice>? members,
    Song? currentTrack,
    bool? isPlaying,
    int? positionMs,
    int? serverTimeMs,
    List<Song>? sharedQueue,
    int? currentIndex,
  }) {
    return SyncGroup(
      code: code ?? this.code,
      name: name ?? this.name,
      hostId: hostId ?? this.hostId,
      hostName: hostName ?? this.hostName,
      hostIp: hostIp ?? this.hostIp,
      port: port ?? this.port,
      members: members ?? this.members,
      currentTrack: currentTrack ?? this.currentTrack,
      isPlaying: isPlaying ?? this.isPlaying,
      positionMs: positionMs ?? this.positionMs,
      serverTimeMs: serverTimeMs ?? this.serverTimeMs,
      sharedQueue: sharedQueue ?? this.sharedQueue,
      currentIndex: currentIndex ?? this.currentIndex,
    );
  }

  Map<String, dynamic> toJson() => {
    'code': code,
    'name': name,
    'host_id': hostId,
    'host_name': hostName,
    'host_ip': hostIp,
    'port': port,
    'members': members.map((m) => m.toJson()).toList(),
    if (currentTrack != null) 'current_track': currentTrack!.toJson(),
    'is_playing': isPlaying,
    'position_ms': positionMs,
    'server_time_ms': serverTimeMs,
    'shared_queue': sharedQueue.map((s) => s.toJson()).toList(),
    'current_index': currentIndex,
  };

  factory SyncGroup.fromJson(Map<String, dynamic> json) => SyncGroup(
    code: json['code']?.toString() ?? '',
    name: json['name']?.toString() ?? 'Sync Group',
    hostId: json['host_id']?.toString() ?? '',
    hostName: json['host_name']?.toString() ?? 'Host',
    hostIp: json['host_ip']?.toString() ?? '',
    port: (json['port'] as num?)?.toInt() ?? 4040,
    members: (json['members'] as List<dynamic>?)
            ?.map((m) => SyncDevice.fromJson(Map<String, dynamic>.from(m as Map)))
            .toList() ??
        const [],
    currentTrack: json['current_track'] != null
        ? Song.fromJson(Map<String, dynamic>.from(json['current_track'] as Map))
        : null,
    isPlaying: json['is_playing'] == true,
    positionMs: (json['position_ms'] as num?)?.toInt() ?? 0,
    serverTimeMs: (json['server_time_ms'] as num?)?.toInt() ?? 0,
    sharedQueue: (json['shared_queue'] as List<dynamic>?)
            ?.map((s) => Song.fromJson(Map<String, dynamic>.from(s as Map)))
            .toList() ??
        const [],
    currentIndex: (json['current_index'] as num?)?.toInt() ?? 0,
  );
}

