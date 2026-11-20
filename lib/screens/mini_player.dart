import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../models/song.dart';
import '../services/audio_service.dart';
import '../theme/app_theme.dart';
import 'lyrics_page.dart';
import 'music_player_page.dart';

class MiniPlayer extends StatefulWidget {
  const MiniPlayer({super.key});

  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer> with TickerProviderStateMixin {
  late final AnimationController _expandController;
  late final Animation<double> _expandAnimation;
  late final AnimationController _spinController;
  Timer? _autoCollapseTimer;

  @override
  void initState() {
    super.initState();
    _expandController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _expandAnimation = CurvedAnimation(
      parent: _expandController,
      curve: Curves.easeInOutCubic,
    );
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 16),
    );
  }

  @override
  void dispose() {
    _autoCollapseTimer?.cancel();
    _expandController.dispose();
    _spinController.dispose();
    super.dispose();
  }

  void _startAutoCollapse() {
    _autoCollapseTimer?.cancel();
    _autoCollapseTimer = Timer(const Duration(seconds: 2), () {
      if (mounted && _expandController.value > 0.05) {
        _collapse();
      }
    });
  }

  void _cancelAutoCollapse() {
    _autoCollapseTimer?.cancel();
    _autoCollapseTimer = null;
  }

  void _expand() {
    _expandController.forward();
    _startAutoCollapse();
  }

  void _collapse() {
    _cancelAutoCollapse();
    _expandController.reverse();
  }

  void _updateSpinning(bool isPlaying) {
    if (isPlaying) {
      if (!_spinController.isAnimating) {
        _spinController.repeat();
      }
    } else {
      if (_spinController.isAnimating) {
        _spinController.stop();
      }
    }
  }

  String _fmt(Duration d) =>
      '${d.inMinutes.toString().padLeft(2, '0')}:${d.inSeconds.remainder(60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final audio = GlobalAudioService();

    return StreamBuilder<int?>(
      stream: audio.currentIndexStream,
      initialData: audio.currentIndex,
      builder: (context, indexSnapshot) {
        final index = indexSnapshot.data;
        final queue = audio.queue;

        if (index == null || index < 0 || index >= queue.length) {
          return const SizedBox.shrink();
        }

        final song = queue[index];

        return FutureBuilder<AudioPlayer>(
          future: audio.player,
          builder: (context, playerSnapshot) {
            final player = playerSnapshot.data;

            return LayoutBuilder(
              builder: (context, constraints) {
                final isDesktop = constraints.maxWidth >= 800;
                if (isDesktop) {
                  return _buildDesktopPlayerBar(context, audio, player, song);
                }
                return _buildMobileMiniPlayer(context, audio, player, song);
              },
            );
          },
        );
      },
    );
  }

  Widget _buildDesktopPlayerBar(
    BuildContext context,
    GlobalAudioService audio,
    AudioPlayer? player,
    Song song,
  ) {
    return Container(
      height: 78,
      decoration: const BoxDecoration(
        color: AppColors.surfaceElevated,
        border: Border(top: BorderSide(color: Colors.white10, width: 1)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        children: [
          // Left: Artwork, song info, quick tap to open player
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MusicPlayerPage()),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      song.imageUrl,
                      width: 50,
                      height: 50,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 50,
                        height: 50,
                        color: AppColors.surface,
                        child: const Icon(
                          Icons.music_note_rounded,
                          color: AppColors.muted,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 180),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          song.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
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
                ],
              ),
            ),
          ),

          const SizedBox(width: 16),

          // Center: Playback Controls & Progress Bar
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 580),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Controls Row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        StreamBuilder<bool>(
                          stream: player?.shuffleModeEnabledStream,
                          initialData: player?.shuffleModeEnabled ?? false,
                          builder: (context, snap) {
                            final shuffle = snap.data ?? false;
                            return IconButton(
                              iconSize: 18,
                              tooltip: 'Shuffle',
                              onPressed: player == null
                                  ? null
                                  : audio.toggleShuffle,
                              icon: Icon(
                                Icons.shuffle_rounded,
                                color: shuffle
                                    ? AppColors.accent
                                    : Colors.white60,
                              ),
                            );
                          },
                        ),
                        IconButton(
                          iconSize: 22,
                          tooltip: 'Previous',
                          onPressed: player == null ? null : audio.previous,
                          icon: const Icon(Icons.skip_previous_rounded),
                        ),
                        const SizedBox(width: 6),
                        StreamBuilder<PlayerState>(
                          stream: player?.playerStateStream,
                          initialData: player?.playerState,
                          builder: (context, state) {
                            final playing = state.data?.playing ?? false;
                            final buffering =
                                state.data?.processingState ==
                                    ProcessingState.buffering ||
                                state.data?.processingState ==
                                    ProcessingState.loading;
                            return Container(
                              width: 36,
                              height: 36,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppColors.accent,
                              ),
                              child: IconButton(
                                padding: EdgeInsets.zero,
                                tooltip: playing ? 'Pause' : 'Play',
                                onPressed: player == null
                                    ? null
                                    : () async {
                                        if (playing) {
                                          await audio.togglePlayback();
                                        } else {
                                          await audio.togglePlayback();
                                        }
                                      },
                                icon: buffering
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : Icon(
                                        playing
                                            ? Icons.pause_rounded
                                            : Icons.play_arrow_rounded,
                                        color: Colors.white,
                                        size: 22,
                                      ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(width: 6),
                        IconButton(
                          iconSize: 22,
                          tooltip: 'Next',
                          onPressed: player == null ? null : audio.next,
                          icon: const Icon(Icons.skip_next_rounded),
                        ),
                        StreamBuilder<LoopMode>(
                          stream: player?.loopModeStream,
                          initialData: player?.loopMode ?? LoopMode.off,
                          builder: (context, snap) {
                            final repeatOne = snap.data == LoopMode.one;
                            return IconButton(
                              iconSize: 18,
                              tooltip: 'Repeat',
                              onPressed: player == null
                                  ? null
                                  : audio.toggleRepeat,
                              icon: Icon(
                                Icons.repeat_rounded,
                                color: repeatOne
                                    ? AppColors.accent
                                    : Colors.white60,
                              ),
                            );
                          },
                        ),
                      ],
                    ),

                    // Progress Slider Row
                    StreamBuilder<Duration>(
                      stream: player?.positionStream,
                      initialData: Duration.zero,
                      builder: (context, posSnap) {
                        return StreamBuilder<Duration?>(
                          stream: player?.durationStream,
                          builder: (context, durSnap) {
                            final pos = posSnap.data ?? Duration.zero;
                            final dur = durSnap.data ?? Duration.zero;
                            final max = dur.inMilliseconds > 0
                                ? dur.inMilliseconds.toDouble()
                                : 1.0;
                            final val = pos.inMilliseconds
                                .clamp(0, max.toInt())
                                .toDouble();

                            return Row(
                              children: [
                                Text(
                                  _fmt(pos),
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: AppColors.muted,
                                  ),
                                ),
                                Expanded(
                                  child: SliderTheme(
                                    data: SliderTheme.of(context).copyWith(
                                      trackHeight: 2.5,
                                      thumbShape: const RoundSliderThumbShape(
                                        enabledThumbRadius: 4.5,
                                      ),
                                      overlayShape:
                                          const RoundSliderOverlayShape(
                                            overlayRadius: 10,
                                          ),
                                    ),
                                    child: Slider(
                                      min: 0,
                                      max: max,
                                      value: val,
                                      activeColor: AppColors.accent,
                                      inactiveColor: Colors.white12,
                                      onChanged: player == null
                                          ? null
                                          : (v) => audio.seek(
                                              Duration(milliseconds: v.toInt()),
                                            ),
                                    ),
                                  ),
                                ),
                                Text(
                                  _fmt(dur),
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: AppColors.muted,
                                  ),
                                ),
                              ],
                            );
                          },
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(width: 16),

          // Right: Shortcuts (Lyrics, Queue, Volume slider)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                iconSize: 20,
                tooltip: 'Lyrics',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => LyricsPage(song: song)),
                ),
                icon: const Icon(Icons.lyrics_outlined, color: Colors.white70),
              ),
              IconButton(
                iconSize: 20,
                tooltip: 'Now Playing & Queue',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const MusicPlayerPage()),
                ),
                icon: const Icon(
                  Icons.queue_music_rounded,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(width: 4),
              StreamBuilder<double>(
                stream: player?.volumeStream,
                initialData: player?.volume ?? 1.0,
                builder: (context, snap) {
                  final vol = snap.data ?? 1.0;
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        iconSize: 18,
                        tooltip: vol > 0 ? 'Mute' : 'Unmute',
                        onPressed: player == null
                            ? null
                            : () => player.setVolume(vol > 0 ? 0.0 : 1.0),
                        icon: Icon(
                          vol == 0
                              ? Icons.volume_off_rounded
                              : (vol < 0.5
                                    ? Icons.volume_down_rounded
                                    : Icons.volume_up_rounded),
                          color: Colors.white70,
                        ),
                      ),
                      SizedBox(
                        width: 80,
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 2.5,
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 4,
                            ),
                            overlayShape: const RoundSliderOverlayShape(
                              overlayRadius: 8,
                            ),
                          ),
                          child: Slider(
                            min: 0,
                            max: 1,
                            value: vol.clamp(0.0, 1.0),
                            activeColor: Colors.white70,
                            inactiveColor: Colors.white12,
                            onChanged: player == null
                                ? null
                                : (v) => player.setVolume(v),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMobileMiniPlayer(
    BuildContext context,
    GlobalAudioService audio,
    AudioPlayer? player,
    Song song,
  ) {
    return StreamBuilder<PlayerState>(
      stream: player?.playerStateStream,
      initialData: player?.playerState,
      builder: (context, state) {
        final isPlaying = state.data?.playing ?? false;
        _updateSpinning(isPlaying);

        return LayoutBuilder(
          builder: (context, constraints) {
            final maxPillWidth = math.min(380.0, constraints.maxWidth - 40.0);

            return AnimatedBuilder(
              animation: _expandAnimation,
              builder: (context, child) {
                final anim = _expandAnimation.value;
                final currentWidth =
                    (64.0 + (maxPillWidth - 64.0) * anim).clamp(64.0, maxPillWidth);
                final currentAlignment = Alignment.lerp(
                  Alignment.bottomRight,
                  Alignment.bottomCenter,
                  anim,
                )!;
                final isCircle = anim < 0.05;

                return Align(
                  alignment: currentAlignment,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanDown: (_) {
                        if (_expandController.value > 0.5) {
                          _cancelAutoCollapse();
                        }
                      },
                      onPanCancel: () {
                        if (_expandController.value > 0.5) {
                          _startAutoCollapse();
                        }
                      },
                      onTap: () {
                        if (_expandController.value < 0.5) {
                          _expand();
                        } else {
                          _startAutoCollapse();
                        }
                      },
                      onHorizontalDragEnd: (details) {
                        if (_expandController.value > 0.5 &&
                            details.primaryVelocity != null &&
                            details.primaryVelocity! > 150) {
                          _collapse();
                        } else if (_expandController.value > 0.5) {
                          _startAutoCollapse();
                        }
                      },
                      onVerticalDragEnd: (details) {
                        if (_expandController.value > 0.5 &&
                            details.primaryVelocity != null &&
                            details.primaryVelocity! > 150) {
                          _collapse();
                        } else if (_expandController.value > 0.5) {
                          _startAutoCollapse();
                        }
                      },
                      child: Container(
                        width: currentWidth,
                        height: 64,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(32),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.35),
                              blurRadius: 20,
                              spreadRadius: 0,
                              offset: const Offset(0, 6),
                            ),
                            BoxShadow(
                              color: AppColors.accent.withValues(
                                alpha: 0.12 * (1.0 + (1.0 - anim) * 0.4),
                              ),
                              blurRadius: isCircle ? 22 : 18,
                              spreadRadius: isCircle ? 0 : -4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(32),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(32),
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    const Color(0xFF222228).withValues(alpha: 0.45),
                                    const Color(0xFF141418).withValues(alpha: 0.30),
                                  ],
                                ),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.16),
                                  width: 1.2,
                                ),
                              ),
                              child: Stack(
                                children: [
                                  // --- Circle Mode View (fades out as it expands) ---
                                  if (anim < 0.95)
                                    Opacity(
                                      opacity: (1.0 - anim * 2.0).clamp(0.0, 1.0),
                                      child: _buildCircleMode(context, audio, player, song),
                                    ),

                                  // --- Pill Mode View (fades in as it expands) ---
                                  if (anim > 0.05)
                                    Opacity(
                                      opacity: ((anim - 0.2) / 0.8).clamp(0.0, 1.0),
                                      child: OverflowBox(
                                        minWidth: maxPillWidth,
                                        maxWidth: maxPillWidth,
                                        minHeight: 64,
                                        maxHeight: 64,
                                        alignment: Alignment.center,
                                        child: _buildPillMode(
                                          context,
                                          audio,
                                          player,
                                          song,
                                          isPlaying,
                                          maxPillWidth,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildCircleMode(
    BuildContext context,
    GlobalAudioService audio,
    AudioPlayer? player,
    Song song,
  ) {
    return Center(
      child: SizedBox(
        width: 64,
        height: 64,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Circular progress indicator ring around the disk
            SizedBox(
              width: 54,
              height: 54,
              child: StreamBuilder<Duration>(
                stream: audio.positionStream,
                initialData: Duration.zero,
                builder: (context, posSnap) {
                  return StreamBuilder<Duration?>(
                    stream: player?.durationStream,
                    initialData: player?.duration,
                    builder: (context, durSnap) {
                      final pos = posSnap.data ?? Duration.zero;
                      final dur = durSnap.data ?? Duration.zero;
                      final progress = dur.inMilliseconds > 0
                          ? (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0)
                          : 0.0;

                      return CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 2.2,
                        backgroundColor: Colors.white.withValues(alpha: 0.12),
                        valueColor: const AlwaysStoppedAnimation<Color>(AppColors.accent),
                      );
                    },
                  );
                },
              ),
            ),

            // Rotating Vinyl / Circular Cover Artwork
            RotationTransition(
              turns: _spinController,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      blurRadius: 6,
                    ),
                  ],
                ),
                child: ClipOval(
                  child: Image.network(
                    song.imageUrl,
                    width: 44,
                    height: 44,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 44,
                      height: 44,
                      color: AppColors.surface,
                      child: const Icon(
                        Icons.music_note_rounded,
                        color: AppColors.muted,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPillMode(
    BuildContext context,
    GlobalAudioService audio,
    AudioPlayer? player,
    Song song,
    bool isPlaying,
    double maxPillWidth,
  ) {
    return SizedBox(
      width: maxPillWidth,
      height: 64,
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                // Cover pic (tapping collapses back to circle)
                GestureDetector(
                  onTap: _collapse,
                  child: Tooltip(
                    message: 'Minimize to circle',
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      child: ClipOval(
                        child: Image.network(
                          song.imageUrl,
                          width: 44,
                          height: 44,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 44,
                            height: 44,
                            color: AppColors.surface,
                            child: const Icon(
                              Icons.music_note_rounded,
                              color: AppColors.muted,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),

                // Title & Artist (taps open full player)
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      _collapse();
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const MusicPlayerPage(),
                        ),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            song.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            song.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Controls: Play/Pause, Next, Collapse
                if (player == null)
                  const SizedBox(
                    width: 40,
                    height: 40,
                    child: Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                else
                  IconButton(
                    tooltip: isPlaying ? 'Pause' : 'Play',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
                    onPressed: () async {
                      _startAutoCollapse();
                      await audio.togglePlayback();
                    },
                    icon: Icon(
                      isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      color: AppColors.accent,
                    ),
                  ),
                IconButton(
                  tooltip: 'Next',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  onPressed: () {
                    _startAutoCollapse();
                    audio.next();
                  },
                  icon: const Icon(Icons.skip_next_rounded, size: 22),
                ),
                IconButton(
                  tooltip: 'Minimize to circle',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: _collapse,
                  icon: const Icon(
                    Icons.unfold_less_rounded,
                    size: 18,
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
          ),

          // Bottom Linear Progress Bar
          Positioned(
            left: 20,
            right: 20,
            bottom: 0,
            child: StreamBuilder<Duration>(
              stream: audio.positionStream,
              initialData: Duration.zero,
              builder: (context, posSnap) {
                return StreamBuilder<Duration?>(
                  stream: player?.durationStream,
                  initialData: player?.duration,
                  builder: (context, durSnap) {
                    final pos = posSnap.data ?? Duration.zero;
                    final dur = durSnap.data ?? Duration.zero;
                    final progress = dur.inMilliseconds > 0
                        ? (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0)
                        : 0.0;

                    return ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(2),
                      ),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 1.5,
                        backgroundColor: Colors.white10,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          AppColors.accent,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
