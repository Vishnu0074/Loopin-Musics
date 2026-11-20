import 'dart:async';
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../models/sync_models.dart';
import '../services/sync_player_service.dart';
import '../theme/app_theme.dart';
import '../widgets/loopin_snackbar.dart';

class SyncPage extends StatefulWidget {
  const SyncPage({super.key});

  @override
  State<SyncPage> createState() => _SyncPageState();
}

class _SyncPageState extends State<SyncPage>
    with SingleTickerProviderStateMixin {
  final _syncService = SyncPlayerService();
  final _joinCodeController = TextEditingController();

  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  double _localVolume = 1.0;
  bool _isCreatingGroup = false;
  bool _isJoiningGroup = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _pulseAnimation = CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _joinCodeController.dispose();
    super.dispose();
  }

  Future<void> _handleCreateGroup() async {
    setState(() => _isCreatingGroup = true);
    try {
      final group = await _syncService.createGroup();
      if (mounted) {
        CustomSnackBar.show(
          context,
          message: 'Created sync group ${group.code}!',
        );
      }
    } catch (e) {
      if (mounted) {
        CustomSnackBar.show(
          context,
          message: 'Failed to create group: $e',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _isCreatingGroup = false);
    }
  }

  Future<void> _handleJoinGroup([String? code]) async {
    final target = (code ?? _joinCodeController.text).trim();
    if (target.isEmpty) {
      CustomSnackBar.show(
        context,
        message: 'Please enter a Sync join code',
        isError: true,
      );
      return;
    }

    setState(() => _isJoiningGroup = true);
    try {
      await _syncService.joinGroup(target);
      if (mounted) {
        CustomSnackBar.show(
          context,
          message: 'Successfully joined sync space!',
        );
        _joinCodeController.clear();
      }
    } catch (e) {
      if (mounted) {
        CustomSnackBar.show(
          context,
          message: 'Could not connect: $e',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _isJoiningGroup = false);
    }
  }

  Future<void> _handleLeaveOrDisband(bool isHost) async {
    final title = isHost ? 'Disband Sync Group?' : 'Leave Sync Group?';
    final content = isHost
        ? 'This will disconnect all members and close the sync group.'
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
        title: Text(title, style: const TextStyle(color: Colors.white)),
        content: Text(
          content,
          style: const TextStyle(color: AppColors.muted, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
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
            child: Text(isHost ? 'Disband' : 'Leave'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _syncService.leaveGroup();
      if (mounted) {
        CustomSnackBar.show(
          context,
          message: isHost ? 'Group disbanded' : 'Left sync group',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SyncRole>(
      stream: _syncService.roleStream,
      initialData: _syncService.role,
      builder: (context, roleSnap) {
        final role = roleSnap.data ?? SyncRole.idle;

        return StreamBuilder<SyncGroup?>(
          stream: _syncService.groupStream,
          initialData: _syncService.group,
          builder: (context, groupSnap) {
            final group = groupSnap.data;
            final inGroup = role != SyncRole.idle && group != null;

            return Scaffold(
              backgroundColor: AppColors.background,
              body: SafeArea(
                bottom: false,
                child: CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: _buildHeader(inGroup, group, role),
                    ),
                    if (!inGroup) ...[
                      SliverToBoxAdapter(child: _buildIdleHeroCards()),
                      SliverToBoxAdapter(child: _buildDiscoveredGroupsSection()),
                      SliverToBoxAdapter(child: _buildHowSyncWorksSection()),
                      const SliverToBoxAdapter(child: SizedBox(height: 120)),
                    ] else ...[
                      SliverToBoxAdapter(
                        child: _buildGroupActiveBanner(group, role),
                      ),
                      SliverToBoxAdapter(
                        child: _buildTelemetryDashboard(role),
                      ),
                      SliverToBoxAdapter(
                        child: _buildNowPlayingSyncCard(group, role),
                      ),
                      SliverToBoxAdapter(
                        child: _buildConnectedDevicesSection(group, role),
                      ),
                      SliverToBoxAdapter(
                        child: _buildSharedQueueSection(group, role),
                      ),
                      const SliverToBoxAdapter(child: SizedBox(height: 140)),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ==========================================
  // HEADER
  // ==========================================

  Widget _buildHeader(bool inGroup, SyncGroup? group, SyncRole role) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Loopin Sync',
                style: AppFonts.display(
                  fontSize: 44,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'Multi-device acoustic surround synchronization',
                style: TextStyle(
                  color: AppColors.muted,
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: inGroup
                      ? AppColors.accent.withValues(alpha: 0.15)
                      : Colors.white.withValues(alpha: 0.06),
                  boxShadow: inGroup
                      ? [
                          BoxShadow(
                            color: AppColors.accent.withValues(
                              alpha: 0.25 * _pulseAnimation.value,
                            ),
                            blurRadius: 16,
                            spreadRadius: 2,
                          ),
                        ]
                      : null,
                  border: Border.all(
                    color: inGroup
                        ? AppColors.accent.withValues(alpha: 0.4)
                        : Colors.white.withValues(alpha: 0.12),
                    width: 1.5,
                  ),
                ),
                child: Icon(
                  Icons.sensors_rounded,
                  color: inGroup ? AppColors.accent : Colors.white70,
                  size: 26,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ==========================================
  // IDLE STATE WIDGETS
  // ==========================================

  Widget _buildIdleHeroCards() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        children: [
          // Create Group Card
          _buildGlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: AppColors.accent.withValues(alpha: 0.3),
                          width: 1,
                        ),
                      ),
                      child: const Icon(
                        Icons.wifi_tethering_rounded,
                        color: AppColors.accent,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Host a Sync Space',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Turn surrounding devices into synchronized speakers',
                            style: TextStyle(
                              color: AppColors.muted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _isCreatingGroup ? null : _handleCreateGroup,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.white,
                      elevation: 4,
                      shadowColor: AppColors.accent.withValues(alpha: 0.4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                    child: _isCreatingGroup
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.add_circle_outline_rounded, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'Create Space & Generate Code',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Join Group Card
          _buildGlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.cyanAccent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.cyanAccent.withValues(alpha: 0.3),
                          width: 1,
                        ),
                      ),
                      child: const Icon(
                        Icons.input_rounded,
                        color: Colors.cyanAccent,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Join a Sync Space',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Enter the 6-character Join Code',
                            style: TextStyle(
                              color: AppColors.muted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.12),
                      width: 1,
                    ),
                  ),
                  child: TextField(
                    controller: _joinCodeController,
                    textCapitalization: TextCapitalization.characters,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                    decoration: InputDecoration(
                      hintText: 'e.g. LP-7A2B',
                      hintStyle: TextStyle(
                        color: Colors.white.withValues(alpha: 0.3),
                        fontSize: 13,
                        letterSpacing: 0.5,
                      ),
                      prefixIcon: const Icon(
                        Icons.tag_rounded,
                        color: Colors.cyanAccent,
                        size: 20,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                    onSubmitted: (val) => _handleJoinGroup(val),
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _isJoiningGroup ? null : () => _handleJoinGroup(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E2638),
                      foregroundColor: Colors.cyanAccent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                        side: BorderSide(
                          color: Colors.cyanAccent.withValues(alpha: 0.4),
                          width: 1.2,
                        ),
                      ),
                    ),
                    child: _isJoiningGroup
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.cyanAccent,
                            ),
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.link_rounded, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'Connect to Space',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiscoveredGroupsSection() {
    return StreamBuilder<List<DiscoveredGroup>>(
      stream: _syncService.discoveredGroupsStream,
      initialData: _syncService.discoveredGroups,
      builder: (context, snap) {
        final groups = snap.data ?? const [];

        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.radar_rounded,
                    color: AppColors.accent,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Nearby Sync Spaces',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  AnimatedBuilder(
                    animation: _pulseAnimation,
                    builder: (context, _) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.greenAccent.withValues(
                          alpha: 0.15 * _pulseAnimation.value,
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.circle,
                            size: 8,
                            color: Colors.greenAccent,
                          ),
                          SizedBox(width: 5),
                          Text(
                            'Scanning Wi-Fi',
                            style: TextStyle(
                              color: Colors.greenAccent,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (groups.isEmpty)
                _buildGlassCard(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.wifi_find_rounded,
                          color: AppColors.muted,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Listening for active Loopin Sync broadcasts on this Wi-Fi network...',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.6),
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                ...groups.map(
                  (group) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _buildGlassCard(
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppColors.accent.withValues(alpha: 0.18),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.speaker_group_rounded,
                              color: AppColors.accent,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  group.groupName,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Host: ${group.hostName} • ${group.membersCount} device${group.membersCount == 1 ? '' : 's'}',
                                  style: const TextStyle(
                                    color: AppColors.muted,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              group.code,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          ElevatedButton(
                            onPressed: () => _handleJoinGroup(group.code),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.accent,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: const Text(
                              'Join',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHowSyncWorksSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Sync Architecture',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          _buildPillarCard(
            icon: Icons.access_time_rounded,
            iconColor: Colors.amberAccent,
            title: 'NTP Clock Synchronization',
            subtitle:
                'Cristian\'s algorithm estimates one-way delays and clock offsets to eliminate timing skew between devices.',
          ),
          const SizedBox(height: 8),
          _buildPillarCard(
            icon: Icons.schedule_send_rounded,
            iconColor: Colors.greenAccent,
            title: 'Scheduled Start Epochs',
            subtitle:
                'Host broadcasts future playback target timestamps so each device pre-buffers and launches at the exact millisecond.',
          ),
          const SizedBox(height: 8),
          _buildPillarCard(
            icon: Icons.tune_rounded,
            iconColor: Colors.cyanAccent,
            title: 'Pitch-Preserved Drift Steering',
            subtitle:
                'Sonic time-stretching dynamically micro-adjusts playback rate (0.96x – 1.04x) to correct audio hardware clock drift seamlessly.',
          ),
        ],
      ),
    );
  }

  Widget _buildPillarCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
  }) {
    return _buildGlassCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 20),
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
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 11,
                    height: 1.3,
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
  // ACTIVE GROUP STATE WIDGETS
  // ==========================================

  Widget _buildGroupActiveBanner(SyncGroup group, SyncRole role) {
    final isHost = role == SyncRole.host;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
      child: _buildGlassCard(
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: isHost
                                  ? Colors.amberAccent.withValues(alpha: 0.2)
                                  : Colors.cyanAccent.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isHost
                                    ? Colors.amberAccent.withValues(alpha: 0.4)
                                    : Colors.cyanAccent.withValues(alpha: 0.4),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isHost
                                      ? Icons.star_rounded
                                      : Icons.satellite_alt_rounded,
                                  size: 14,
                                  color: isHost
                                      ? Colors.amberAccent
                                      : Colors.cyanAccent,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  isHost ? 'Master Host' : 'Synced Receiver',
                                  style: TextStyle(
                                    color: isHost
                                        ? Colors.amberAccent
                                        : Colors.cyanAccent,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            group.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Text(
                            'Join Code: ',
                            style: TextStyle(
                              color: AppColors.muted,
                              fontSize: 13,
                            ),
                          ),
                          GestureDetector(
                            onTap: () {
                              Clipboard.setData(
                                ClipboardData(text: group.code),
                              );
                              CustomSnackBar.show(
                                context,
                                message: 'Join code copied to clipboard!',
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.2),
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    group.code,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  const Icon(
                                    Icons.copy_rounded,
                                    size: 14,
                                    color: AppColors.muted,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          IconButton(
                            icon: const Icon(
                              Icons.share_rounded,
                              size: 18,
                              color: AppColors.muted,
                            ),
                            tooltip: 'Share Space',
                            onPressed: () {
                              Share.share(
                                'Join my Loopin Sync audio space with code: ${group.code}',
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(
                    isHost
                        ? Icons.power_settings_new_rounded
                        : Icons.logout_rounded,
                    color: isHost ? Colors.redAccent : Colors.white70,
                    size: 24,
                  ),
                  tooltip: isHost ? 'Disband Group' : 'Leave Group',
                  onPressed: () => _handleLeaveOrDisband(isHost),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTelemetryDashboard(SyncRole role) {
    return StreamBuilder<SyncDevice>(
      stream: _syncService.localDeviceStream,
      initialData: _syncService.localDevice,
      builder: (context, snap) {
        final device = snap.data ?? _syncService.localDevice;
        final isHost = role == SyncRole.host;

        Color statusColor = Colors.greenAccent;
        String statusLabel = 'In Sync';
        if (device.status == SyncConnectionStatus.adjusting) {
          statusColor = Colors.orangeAccent;
          statusLabel = 'Steering Tempo';
        } else if (device.status == SyncConnectionStatus.syncing) {
          statusColor = Colors.cyanAccent;
          statusLabel = 'Syncing Phase';
        } else if (device.status == SyncConnectionStatus.connecting) {
          statusColor = Colors.amberAccent;
          statusLabel = 'Connecting';
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          child: _buildGlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Acoustic Telemetry',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.circle, size: 7, color: statusColor),
                          const SizedBox(width: 5),
                          Text(
                            isHost ? 'Authoritative Clock' : statusLabel,
                            style: TextStyle(
                              color: statusColor,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildMetricTile(
                        label: 'Round-Trip Latency',
                        value: isHost ? '0 ms' : '${device.latencyMs} ms',
                        icon: Icons.speed_rounded,
                        accentColor: Colors.cyanAccent,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildMetricTile(
                        label: 'Clock Offset (θ)',
                        value: isHost
                            ? 'Master'
                            : '${device.clockOffsetMs >= 0 ? "+" : ""}${device.clockOffsetMs} ms',
                        icon: Icons.schedule_rounded,
                        accentColor: Colors.amberAccent,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildMetricTile(
                        label: 'Drift Delta',
                        value: isHost
                            ? '0 ms'
                            : '${device.driftMs >= 0 ? "+" : ""}${device.driftMs} ms',
                        icon: Icons.compare_arrows_rounded,
                        accentColor: Colors.greenAccent,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMetricTile({
    required String label,
    required String value,
    required IconData icon,
    required Color accentColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Icon(icon, color: accentColor, size: 16),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNowPlayingSyncCard(SyncGroup group, SyncRole role) {
    final track = group.currentTrack;
    final isHost = role == SyncRole.host;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: _buildGlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: track?.imageUrl.isNotEmpty == true
                      ? Image.network(
                          track!.imageUrl,
                          width: 60,
                          height: 60,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _albumArtPlaceholder(),
                        )
                      : _albumArtPlaceholder(),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track?.title ?? 'No Track Playing',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        track?.artist ?? 'Select a song from Queue',
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

            // Controls
            if (isHost) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.skip_previous_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                    onPressed: () => _syncService.hostPreviousTrack(),
                  ),
                  const SizedBox(width: 16),
                  Container(
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.accent,
                    ),
                    child: IconButton(
                      icon: Icon(
                        group.isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 32,
                      ),
                      onPressed: () {
                        if (group.isPlaying) {
                          _syncService.hostPause();
                        } else {
                          _syncService.hostSchedulePlay();
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  IconButton(
                    icon: const Icon(
                      Icons.skip_next_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                    onPressed: () => _syncService.hostNextTrack(),
                  ),
                ],
              ),
            ] else ...[
              // Follower Speaker Volume
              Row(
                children: [
                  const Icon(
                    Icons.volume_down_rounded,
                    color: AppColors.muted,
                    size: 20,
                  ),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: AppColors.accent,
                        inactiveTrackColor: Colors.white12,
                        thumbColor: Colors.white,
                        trackHeight: 3,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 6,
                        ),
                      ),
                      child: Slider(
                        value: _localVolume,
                        onChanged: (val) {
                          setState(() => _localVolume = val);
                          _syncService.setLocalVolume(val);
                        },
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.volume_up_rounded,
                    color: AppColors.muted,
                    size: 20,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _albumArtPlaceholder() {
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(Icons.music_note_rounded, color: AppColors.muted),
    );
  }

  Widget _buildConnectedDevicesSection(SyncGroup group, SyncRole role) {
    final isHost = role == SyncRole.host;
    final members = group.members;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Connected Devices (${members.length})',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (isHost)
                const Text(
                  'Host controls kick permissions',
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: 11,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          ...members.map((device) {
            final isSelf = device.id == _syncService.localDevice.id;

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              child: _buildGlassCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Icon(
                      _getPlatformIcon(device.platform),
                      color: device.isHost
                          ? Colors.amberAccent
                          : Colors.cyanAccent,
                      size: 22,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                device.name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (isSelf)
                                Container(
                                  margin: const EdgeInsets.only(left: 6),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    'You',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 10,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            device.isHost
                                ? 'Master Clock Source'
                                : 'RTT: ${device.latencyMs}ms • Drift: ${device.driftMs}ms',
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isHost && !device.isHost)
                      IconButton(
                        icon: const Icon(
                          Icons.remove_circle_outline_rounded,
                          color: Colors.redAccent,
                          size: 20,
                        ),
                        tooltip: 'Remove Device',
                        onPressed: () => _syncService.kickDevice(device.id),
                      ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  IconData _getPlatformIcon(String platform) {
    final lower = platform.toLowerCase();
    if (lower.contains('mac') || lower.contains('ios') || lower.contains('darwin')) {
      return Icons.apple_rounded;
    }
    if (lower.contains('android')) return Icons.android_rounded;
    if (lower.contains('win')) return Icons.desktop_windows_rounded;
    if (lower.contains('linux')) return Icons.computer_rounded;
    return Icons.devices_rounded;
  }

  Widget _buildSharedQueueSection(SyncGroup group, SyncRole role) {
    final queue = group.sharedQueue;
    final isHost = role == SyncRole.host;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Shared Space Queue (${queue.length})',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (isHost)
                const Text(
                  'Tap song to schedule play',
                  style: TextStyle(color: AppColors.muted, fontSize: 11),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (queue.isEmpty)
            _buildGlassCard(
              child: const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'No songs in shared queue. Play tracks in Loopin to sync.',
                    style: TextStyle(color: AppColors.muted, fontSize: 13),
                  ),
                ),
              ),
            )
          else
            ...List.generate(queue.length, (index) {
              final song = queue[index];
              final isCurrent = index == group.currentIndex;

              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                child: _buildGlassCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  borderColor: isCurrent
                      ? AppColors.accent.withValues(alpha: 0.4)
                      : null,
                  child: Row(
                    children: [
                      Text(
                        '${index + 1}',
                        style: TextStyle(
                          color: isCurrent
                              ? AppColors.accent
                              : Colors.white.withValues(alpha: 0.4),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: song.imageUrl.isNotEmpty
                            ? Image.network(
                                song.imageUrl,
                                width: 40,
                                height: 40,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    _miniSongPlaceholder(),
                              )
                            : _miniSongPlaceholder(),
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
                              style: TextStyle(
                                color: isCurrent
                                    ? AppColors.accent
                                    : Colors.white,
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
                      if (isHost) ...[
                        IconButton(
                          icon: Icon(
                            isCurrent && group.isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            color: isCurrent
                                ? AppColors.accent
                                : Colors.white70,
                            size: 20,
                          ),
                          onPressed: () {
                            if (isCurrent && group.isPlaying) {
                              _syncService.hostPause();
                            } else {
                              _syncService.hostSchedulePlay(
                                song: song,
                                positionMs: 0,
                              );
                            }
                          },
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.close_rounded,
                            color: AppColors.muted,
                            size: 18,
                          ),
                          onPressed: () =>
                              _syncService.hostRemoveFromQueue(index),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _miniSongPlaceholder() {
    return Container(
      width: 40,
      height: 40,
      color: Colors.white.withValues(alpha: 0.08),
      child: const Icon(
        Icons.music_note_rounded,
        color: AppColors.muted,
        size: 18,
      ),
    );
  }

  // ==========================================
  // REUSABLE GLASS CARD
  // ==========================================

  Widget _buildGlassCard({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(16),
    Color? borderColor,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 16,
            spreadRadius: 0,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF24242A).withValues(alpha: 0.55),
                  const Color(0xFF141418).withValues(alpha: 0.40),
                ],
              ),
              border: Border.all(
                color: borderColor ?? Colors.white.withValues(alpha: 0.12),
                width: 1.2,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
