import 'package:flutter_test/flutter_test.dart';
import 'package:loopin/models/song.dart';
import 'package:loopin/models/sync_models.dart';

void main() {
  group('Sync Models & Logic Tests', () {
    test('SyncDevice serialization and quality calculation', () {
      final device = SyncDevice(
        id: 'dev_123',
        name: 'Pixel 8',
        platform: 'android',
        ipAddress: '192.168.1.100',
        isHost: false,
        latencyMs: 18,
        clockOffsetMs: 5,
        driftMs: -2,
        status: SyncConnectionStatus.synced,
        joinedAt: DateTime(2026, 11, 7, 20, 0),
      );

      expect(device.quality, SyncQuality.excellent);

      final json = device.toJson();
      final recovered = SyncDevice.fromJson(json);

      expect(recovered.id, 'dev_123');
      expect(recovered.name, 'Pixel 8');
      expect(recovered.platform, 'android');
      expect(recovered.latencyMs, 18);
      expect(recovered.clockOffsetMs, 5);
      expect(recovered.driftMs, -2);
      expect(recovered.status, SyncConnectionStatus.synced);
    });

    test('SyncQuality thresholds', () {
      final excellent = SyncDevice(
        id: '1',
        name: 'D1',
        platform: 'mac',
        ipAddress: '',
        latencyMs: 25,
        joinedAt: DateTime.now(),
      );
      final good = excellent.copyWith(latencyMs: 60);
      final fair = excellent.copyWith(latencyMs: 120);
      final poor = excellent.copyWith(latencyMs: 250);

      expect(excellent.quality, SyncQuality.excellent);
      expect(good.quality, SyncQuality.good);
      expect(fair.quality, SyncQuality.fair);
      expect(poor.quality, SyncQuality.poor);
    });

    test('SyncGroup serialization with currentTrack and sharedQueue', () {
      const song1 = Song(
        id: 's1',
        title: 'Song One',
        artist: 'Artist A',
        imageUrl: 'https://example.com/1.jpg',
        mediaUrl: 'https://example.com/1.mp3',
      );
      const song2 = Song(
        id: 's2',
        title: 'Song Two',
        artist: 'Artist B',
        imageUrl: 'https://example.com/2.jpg',
        mediaUrl: 'https://example.com/2.mp3',
      );

      final group = SyncGroup(
        code: 'LP-9988',
        name: 'Living Room Space',
        hostId: 'host_1',
        hostName: 'MacBook Host',
        hostIp: '192.168.1.50',
        port: 4040,
        currentTrack: song1,
        isPlaying: true,
        positionMs: 15400,
        sharedQueue: const [song1, song2],
        currentIndex: 0,
      );

      final json = group.toJson();
      final recovered = SyncGroup.fromJson(json);

      expect(recovered.code, 'LP-9988');
      expect(recovered.name, 'Living Room Space');
      expect(recovered.currentTrack?.id, 's1');
      expect(recovered.isPlaying, true);
      expect(recovered.positionMs, 15400);
      expect(recovered.sharedQueue.length, 2);
      expect(recovered.sharedQueue[1].title, 'Song Two');
    });

    test('NTP Clock Synchronization Math (Cristian Formula)', () {
      // Simulate follow clock is 500ms behind host clock:
      // Host clock = Follower clock + 500ms
      const t1 = 1000; // follower send
      const t2 = 1510; // host receive (1010 follower time + 500ms clock offset)
      const t3 = 1512; // host reply
      const t4 = 1022; // follower receive (12ms return delay)

      // RTT = (T4 - T1) - (T3 - T2)
      final rtt = (t4 - t1) - (t3 - t2);
      expect(rtt, (1022 - 1000) - (1512 - 1510)); // 22 - 2 = 20ms

      // Offset theta = ((T2 - T1) + (T3 - T4)) / 2
      final offset = (((t2 - t1) + (t3 - t4)) / 2).round();
      // ((1510 - 1000) + (1512 - 1022)) / 2 = (510 + 490) / 2 = 500ms
      expect(offset, 500);

      // Estimated host time at T4:
      final estimatedHostTime = t4 + offset;
      // Actual host time at T4 was T3 + one-way trip = 1512 + 10 = 1522ms
      expect(estimatedHostTime, 1522);
    });

    test('Scheduled Playback Start Delay Calculation', () {
      const clockOffset = 120; // Host is 120ms ahead
      const nowLocal = 10000;
      final nowHost = nowLocal + clockOffset; // 10120

      const leadTimeMs = 800;
      final targetEpochMs = nowHost + leadTimeMs; // 10920

      // Follower computes local target:
      final localTarget = targetEpochMs - clockOffset; // 10800
      final delayToFire = localTarget - nowLocal;

      expect(delayToFire, leadTimeMs); // Exactly 800ms wait
    });

    test('Multi-Tier Drift Steering Logic', () {
      double computeSteeringSpeed(int driftMs) {
        final abs = driftMs.abs();
        if (abs <= 25) return 1.0;
        if (abs <= 320) {
          return driftMs < 0 ? 1.04 : 0.96;
        }
        return 1.0; // Medium or hard drift performs seeks
      }

      // Micro drift (< 25ms) maintains normal speed
      expect(computeSteeringSpeed(12), 1.0);
      expect(computeSteeringSpeed(-20), 1.0);

      // Minor drift (lagging behind host by 100ms): speeds up to 1.04x
      expect(computeSteeringSpeed(-100), 1.04);

      // Minor drift (ahead of host by 150ms): slows down to 0.96x
      expect(computeSteeringSpeed(150), 0.96);

      // Out of bounds drift triggers seek instead of tempo distortion
      expect(computeSteeringSpeed(500), 1.0);
    });
  });
}

