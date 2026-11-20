import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../models/song.dart';
import '../services/audio_service.dart';
import '../services/audio_output_service.dart';
import '../services/lyrics_service.dart';
import '../services/recommendation_service.dart';
import '../services/playlist_service.dart';
import 'playlists_page.dart';
import '../theme/app_theme.dart';
import 'lyrics_page.dart';
import '../widgets/loopin_snackbar.dart';

class MusicPlayerPage extends StatefulWidget {
  final Song? initialSong;
  const MusicPlayerPage({super.key, this.initialSong});
  @override State<MusicPlayerPage> createState() => _MusicPlayerPageState();
}
class _MusicPlayerPageState extends State<MusicPlayerPage> {
  final _audio = GlobalAudioService();
  final _audioOutput = AudioOutputService();
  final _recommendations = RecommendationService();
  AudioPlayer? _player;
  StreamSubscription<int?>? _indexSub;
  StreamSubscription<List<Song>>? _queueSub;
  Set<String> _likedIds = {};
  final Set<String> _dislikedIds = {};
  bool _changingTrack = false;
  @override void initState() { super.initState(); _init(); }
  Future<void> _init() async {
    final player = await _audio.player;
    final ids = await _recommendations.loadLikedIds();
    if (!mounted) return;
    _player = player;
    _likedIds = ids;
    _preloadLyrics();
    _indexSub = _audio.currentIndexStream.listen((_) async {
      if (!mounted) return;
      _preloadLyrics();
      final song = _current;
      if (song != null) {
        final ids = await _recommendations.loadLikedIds();
        if (mounted) setState(() => _likedIds = ids);
      }
      if (mounted) setState(() {});
    });
    _queueSub = _audio.queueStream.listen((_) {
      _preloadLyrics();
      if (mounted) setState(() {});
    });
    setState(() {});
  }
  @override void dispose() { _indexSub?.cancel(); _queueSub?.cancel(); super.dispose(); }

  void _preloadLyrics() {
    final song = _current;
    if (song != null) {
      LyricsService.preload(song);
    }
    LyricsService.preloadQueue(_audio.queue, _audio.currentIndex ?? 0);
  }

  Song? get _current {
    final index = _audio.currentIndex;
    final queue = _audio.queue;
    if (index == null || index < 0 || index >= queue.length) return widget.initialSong;
    return queue[index];
  }
  String _duration(Duration value) => '${value.inMinutes.toString().padLeft(2, '0')}:${value.inSeconds.remainder(60).toString().padLeft(2, '0')}';

  @override Widget build(BuildContext context) {
    final song = _current;
    final player = _player;
    if (song == null) return const Scaffold(backgroundColor: AppColors.background, body: Center(child: Text('Nothing is playing')));
    return Scaffold(
      backgroundColor: Colors.black,
      body: StreamBuilder<SequenceState?>(
        stream: player?.sequenceStateStream,
        builder: (context, _) => Stack(
          fit: StackFit.expand,
          children: [
            _background(_current ?? song),
            SafeArea(
              child: LayoutBuilder(builder: (context, constraints) {
                final isDesktop = constraints.maxWidth >= 900;
                if (isDesktop) {
                  return Column(
                    children: [
                      _header(),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(40, 10, 40, 30),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // Left: Player controls and Artwork
                              Expanded(
                                flex: 5,
                                child: Center(
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(maxWidth: 440),
                                    child: SingleChildScrollView(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          _artwork(_current ?? song),
                                          const SizedBox(height: 20),
                                          _metadata(_current ?? song),
                                          const SizedBox(height: 16),
                                          _progress(player),
                                          const SizedBox(height: 8),
                                          _mainControls(player),
                                          const SizedBox(height: 14),
                                          _secondaryActions(),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 40),
                              // Right: Queue & Lyrics side panel
                              Expanded(
                                flex: 5,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.35),
                                    borderRadius: BorderRadius.circular(24),
                                    border: Border.all(color: Colors.white10),
                                  ),
                                  padding: const EdgeInsets.all(20),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          const Icon(Icons.queue_music_rounded, color: AppColors.accent, size: 20),
                                          const SizedBox(width: 8),
                                          const Text(
                                            'UPCOMING QUEUE',
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: 1.5,
                                            ),
                                          ),
                                          const Spacer(),
                                          Text(
                                            '${_audio.queue.length} songs',
                                            style: const TextStyle(fontSize: 12, color: AppColors.muted),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      const Divider(height: 1, color: Colors.white10),
                                      const SizedBox(height: 12),
                                      Expanded(
                                        child: _desktopQueueList(),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                }

                return Column(children: [
                  _header(),
                  Expanded(child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(22, 12, 22, 30),
                    child: Column(children: [
                      _artwork(_current ?? song),
                      const SizedBox(height: 24),
                      _metadata(_current ?? song),
                      const SizedBox(height: 20),
                      _progress(player),
                      const SizedBox(height: 8),
                      _mainControls(player),
                      const SizedBox(height: 18),
                      _secondaryActions(),
                      const SizedBox(height: 22),
                      _upNext(),
                    ]),
                  )),
                ]);
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _desktopQueueList() {
    final queue = _audio.queue;
    final currentIdx = _audio.currentIndex ?? 0;
    if (queue.isEmpty) {
      return const Center(child: Text('Queue is empty', style: TextStyle(color: AppColors.muted)));
    }
    return ReorderableListView.builder(
      buildDefaultDragHandles: false,
      itemCount: queue.length,
      onReorderItem: (oldIndex, newIndex) =>
          unawaited(_audio.reorderQueue(oldIndex, newIndex)),
      itemBuilder: (context, index) {
        final song = queue[index];
        final isCurrent = index == currentIdx;
        return Material(
          key: ValueKey(song.id),
          type: MaterialType.transparency,
          child: ListTile(
            dense: true,
            selected: isCurrent,
            selectedTileColor: AppColors.accent.withValues(alpha: 0.15),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                song.imageUrl,
                width: 40,
                height: 40,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox(
                  width: 40,
                  height: 40,
                  child: ColoredBox(color: AppColors.surfaceElevated, child: Icon(Icons.music_note_rounded, size: 20)),
                ),
              ),
            ),
            title: Text(
              song.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                color: isCurrent ? AppColors.accent : Colors.white,
              ),
            ),
            subtitle: Text(
              song.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: AppColors.muted),
            ),
            trailing: isCurrent
                ? const Icon(Icons.graphic_eq_rounded, color: AppColors.accent, size: 18)
                : ReorderableDragStartListener(
                    index: index,
                    child: const Icon(Icons.drag_handle_rounded, color: Colors.white38),
                  ),
            onTap: () async {
              await _audio.playAtIndex(index);
            },
          ),
        );
      },
    );
  }

  Widget _background(Song song) => Stack(fit: StackFit.expand, children: [
    Image.network(song.imageUrl, fit: BoxFit.cover, filterQuality: FilterQuality.high),
    BackdropFilter(filter: ImageFilter.blur(sigmaX: 45, sigmaY: 45), child: Container(color: Colors.black.withValues(alpha: .76))),
    DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(
      begin: Alignment.topCenter, end: Alignment.bottomCenter,
      colors: [Colors.black.withValues(alpha: .15), Colors.black.withValues(alpha: .48), Colors.black.withValues(alpha: .97)],
    ))),
  ]);

  Widget _header() => Padding(
    padding: const EdgeInsets.fromLTRB(10, 4, 10, 0),
    child: Row(children: [
      IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 31)),
      const Expanded(child: Column(children: [
        Text('LOOPIN', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 3)),
        SizedBox(height: 3), Text('NOW PLAYING', style: TextStyle(fontSize: 9, color: Colors.white54, letterSpacing: 1.8)),
      ])),
      IconButton(onPressed: _showQueue, icon: const Icon(Icons.queue_music_rounded)),
    ]),
  );

  Widget _artwork(Song song) => Hero(tag: 'player-art-${song.id}', child: Container(
    constraints: const BoxConstraints(maxWidth: 390),
    decoration: BoxDecoration(borderRadius: BorderRadius.circular(28), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .5), blurRadius: 42, offset: const Offset(0, 18))]),
    child: ClipRRect(borderRadius: BorderRadius.circular(28), child: AspectRatio(aspectRatio: 1, child: Image.network(
      song.imageUrl, fit: BoxFit.cover, filterQuality: FilterQuality.high,
      errorBuilder: (_, __, ___) => const ColoredBox(color: AppColors.surfaceElevated, child: Icon(Icons.music_note_rounded, size: 80)),
    ))),
  ));

  Widget _metadata(Song song) => Row(children: [
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(song.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 25, height: 1.12, fontWeight: FontWeight.w800)),
      const SizedBox(height: 7),
      Text(song.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.accent, fontSize: 15, fontWeight: FontWeight.w600)),
      if ((song.album ?? '').isNotEmpty) ...[const SizedBox(height: 4), Text(song.album!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white54, fontSize: 12))],
    ])),
    IconButton(onPressed: _showSongActions, icon: const Icon(Icons.more_horiz_rounded)),
  ]);

  Widget _progress(AudioPlayer? player) => StreamBuilder<Duration>(
    stream: player?.positionStream, initialData: Duration.zero,
    builder: (context, positionSnapshot) => StreamBuilder<Duration?>(
      stream: player?.durationStream,
      builder: (context, durationSnapshot) {
        final position = positionSnapshot.data ?? Duration.zero;
        final duration = durationSnapshot.data ?? Duration.zero;
        final max = duration.inMilliseconds > 0 ? duration.inMilliseconds.toDouble() : 1.0;
        final value = position.inMilliseconds.clamp(0, max.toInt()).toDouble();
        return Column(children: [
          SliderTheme(data: SliderTheme.of(context).copyWith(trackHeight: 3, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5), overlayShape: const RoundSliderOverlayShape(overlayRadius: 14)),
            child: Slider(min: 0, max: max, value: value, activeColor: AppColors.accent, inactiveColor: Colors.white24, onChanged: player == null ? null : (v) => _audio.seek(Duration(milliseconds: v.toInt())))),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(_duration(position), style: const TextStyle(color: Colors.white54, fontSize: 11)),
            Text(_duration(duration), style: const TextStyle(color: Colors.white54, fontSize: 11)),
          ]),
        ]);
      },
    ),
  );

  Widget _mainControls(AudioPlayer? player) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      _modeButton(Icons.shuffle_rounded, player?.shuffleModeEnabled == true, player == null ? null : _audio.toggleShuffle),
      IconButton(iconSize: 38, onPressed: player == null ? null : () { _audio.previous(); _preloadLyrics(); }, icon: const Icon(Icons.skip_previous_rounded)),
      GestureDetector(
        onTap: player == null ? null : () async {
          await _audio.togglePlayback();
        },
        child: Container(width: 74, height: 74, decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
          child: StreamBuilder<PlayerState>(
            stream: player?.playerStateStream,
            builder: (context, snapshot) {
              final state = snapshot.data;
              final loading = state?.processingState == ProcessingState.loading || state?.processingState == ProcessingState.buffering;
              return Center(child: loading ? const SizedBox(width: 25, height: 25, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)) : Icon(state?.playing == true ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.white, size: 40));
            },
          ),
        ),
      ),
      IconButton(
        iconSize: 38,
        onPressed: player == null || _changingTrack ? null : () async {
          setState(() => _changingTrack = true);
          try {
            await _audio.next();
            _preloadLyrics();
          } finally {
            if (mounted) setState(() => _changingTrack = false);
          }
        },
        icon: const Icon(Icons.skip_next_rounded),
      ),
      _modeButton(Icons.repeat_rounded, player?.loopMode == LoopMode.one, player == null ? null : _audio.toggleRepeat),
    ],
  );

  Widget _modeButton(IconData icon, bool active, VoidCallback? onTap) => IconButton(onPressed: onTap, icon: Icon(icon, color: active ? AppColors.accent : Colors.white70));

  Widget _secondaryActions() => Row(children: [
    _actionTile(
      _likedIds.contains(_current?.id) ? Icons.favorite_rounded : Icons.favorite_border_rounded,
      _likedIds.contains(_current?.id) ? 'Liked' : 'Like',
      () async {
        final song = _current;
        if (song == null) return;
        final liked = !_likedIds.contains(song.id);

        // Optimistic UI: update the player immediately and let the backend sync
        // happen in the background. Roll back only if that request fails.
        _recommendations.setLikeLocally(song.id, liked);
        if (mounted) {
          setState(() {
            if (liked) {
              _likedIds.add(song.id);
              _dislikedIds.remove(song.id);
            } else {
              _likedIds.remove(song.id);
            }
          });
          LoopinSnackBar.show(context, liked ? 'Saved to liked songs.' : 'Removed from liked songs.', type: LoopinSnackBarType.success);
        }

        try {
          await _recommendations.syncLike(song, liked);
        } catch (error) {
          _recommendations.setLikeLocally(song.id, !liked);
          if (!mounted) return;
          setState(() {
            if (liked) {
              _likedIds.remove(song.id);
            } else {
              _likedIds.add(song.id);
            }
          });
          LoopinSnackBar.show(context, 'Could not sync like: $error', type: LoopinSnackBarType.error);
        }
      },
    ),
    const SizedBox(width: 10),
    _actionTile(
      _dislikedIds.contains(_current?.id) ? Icons.thumb_down_rounded : Icons.thumb_down_off_alt_rounded,
      _dislikedIds.contains(_current?.id) ? 'Disliked' : 'Dislike',
      () async {
        final song = _current;
        if (song == null) return;
        try {
          await _recommendations.recordDislike(song);
          if (!mounted) return;
          setState(() {
            _dislikedIds.add(song.id);
            _likedIds.remove(song.id);
          });
          LoopinSnackBar.show(context, 'We will recommend less like this.');
        } catch (error) {
          if (mounted) LoopinSnackBar.show(context, error.toString());
        }
      },
    ),
    const SizedBox(width: 10),
    _actionTile(Icons.playlist_add_rounded, 'Playlist', _showPlaylistPicker),
    const SizedBox(width: 10),
    _actionTile(Icons.speaker_group_rounded, 'Audio', _showAudioOutputPicker),
    const SizedBox(width: 10),
    _actionTile(Icons.lyrics_outlined, 'Lyrics', () {
      final song = _current;
      if (song == null) return;
      Navigator.push(context, MaterialPageRoute(builder: (_) => LyricsPage(song: song)));
    }),
  ]);

  Future<void> _showAudioOutputPicker() async {
    final outputs = await _audioOutput.availableOutputs();
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: false,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Row(
                children: [
                  Icon(Icons.speaker_group_rounded, color: AppColors.accent),
                  SizedBox(width: 10),
                  Text('Audio output', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Loopin follows Android’s media output route. Connect your Bluetooth device, then select it from Android’s media output controls.',
                style: TextStyle(color: AppColors.muted, fontSize: 12),
              ),
              const SizedBox(height: 14),
              if (_audioOutput.isAndroid) ...[
                const Text(
                  'DETECTED OUTPUTS',
                  style: TextStyle(color: AppColors.muted, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.3),
                ),
                const SizedBox(height: 8),
                if (outputs.isEmpty)
                  const ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.speaker_outlined, color: Colors.white70),
                    title: Text('System default'),
                    subtitle: Text('No additional output device detected', style: TextStyle(color: AppColors.muted, fontSize: 11)),
                  )
                else
                  ...outputs.map((device) {
                    final bluetooth = device['isBluetooth'] == true;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        bluetooth ? Icons.bluetooth_rounded : Icons.speaker_rounded,
                        color: bluetooth ? AppColors.accent : Colors.white70,
                      ),
                      title: Text(device['name']?.toString() ?? 'Audio device'),
                      subtitle: Text(
                        device['type']?.toString() ?? 'Available media output',
                        style: const TextStyle(color: AppColors.muted, fontSize: 11),
                      ),
                    );
                  }),
                const SizedBox(height: 6),
                const Text(
                  'Android does not expose a public API for ordinary apps to force other apps onto a different speaker. Some phone manufacturers provide a separate-app audio feature in system settings.',
                  style: TextStyle(color: AppColors.muted, fontSize: 11, height: 1.4),
                ),
              ] else
                const Text(
                  'Audio output routing is managed by your operating system.',
                  style: TextStyle(color: AppColors.muted, fontSize: 12),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionTile(IconData icon, String label, [VoidCallback? onTap]) => Expanded(child: Material(
    color: Colors.white.withValues(alpha: .08), borderRadius: BorderRadius.circular(16),
    child: InkWell(
      onTap: onTap ?? () => LoopinSnackBar.show(context, '$label is coming next in Loopin.'),
      borderRadius: BorderRadius.circular(16),
      child: Padding(padding: const EdgeInsets.symmetric(vertical: 11), child: Column(children: [
        Icon(icon, size: 19, color: Colors.white70), const SizedBox(height: 5),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.white60)),
      ])),
    ),
  ));

  Widget _upNext() {
    final index = _audio.currentIndex ?? -1;
    final queue = _audio.queue;
    final next = index >= 0 && index + 1 < queue.length ? queue.skip(index + 1).take(3).toList() : <Song>[];
    return Container(
      width: double.infinity, padding: const EdgeInsets.fromLTRB(16, 15, 10, 8),
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: .3), borderRadius: BorderRadius.circular(22), border: Border.all(color: Colors.white.withValues(alpha: .08))),
      child: Column(children: [
        Row(children: [
          const Expanded(child: Text('UP NEXT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.8))),
          TextButton(onPressed: _showQueue, child: const Text('See all')),
        ]),
        if (next.isEmpty)
          const Padding(padding: EdgeInsets.fromLTRB(0, 8, 0, 14), child: Row(children: [
            Icon(Icons.auto_awesome_rounded, size: 18, color: Colors.white54), SizedBox(width: 10),
            Expanded(child: Text('Building your next songs…', style: TextStyle(color: Colors.white54, fontSize: 12))),
          ]))
        else ...next.asMap().entries.map((entry) => _nextTile(entry.key + 1, entry.value)),
      ]),
    );
  }

  Widget _nextTile(int number, Song song) => Material(
    type: MaterialType.transparency,
    child: ListTile(
      contentPadding: EdgeInsets.zero, dense: true,
      leading: ClipRRect(borderRadius: BorderRadius.circular(9), child: Image.network(song.imageUrl, width: 42, height: 42, fit: BoxFit.cover, filterQuality: FilterQuality.high,
        errorBuilder: (_, __, ___) => const SizedBox(width: 42, height: 42, child: ColoredBox(color: AppColors.surfaceElevated, child: Icon(Icons.music_note_rounded))))),
      title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
      subtitle: Text(song.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white54, fontSize: 11)),
      trailing: Text(number.toString().padLeft(2, '0'), style: const TextStyle(color: Colors.white24, fontSize: 11)),
      onTap: () async {
        final index = _audio.queue.indexOf(song);
        if (index < 0) return;
        await _audio.playAtIndex(index);
      },
    ),
  );

  void _showQueue() {
    showModalBottomSheet<void>(context: context, backgroundColor: AppColors.surface, isScrollControlled: true, builder: (_) => const _QueueSheet());
  }

  Future<void> _showPlaylistPicker() async {
    final song = _current;
    if (song == null) return;
    final api = PlaylistService();
    try {
      final playlists = await api.list();
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: AppColors.surface,
        builder: (sheetContext) => SafeArea(
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.all(18),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Add to playlist', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  ),
                ),
                if (playlists.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(18),
                    child: Text('No playlists yet. Create one from Library.'),
                  ),
                ...playlists.map(
                  (playlist) => ListTile(
                    leading: const Icon(Icons.queue_music_rounded),
                    title: Text(playlist.name),
                    subtitle: Text('${playlist.songCount} songs'),
                    onTap: () async {
                      try {
                        await api.addSong(playlist.id, song);
                        if (sheetContext.mounted) Navigator.pop(sheetContext);
                        if (mounted) {
                          LoopinSnackBar.show(context, 'Added to ${playlist.name}');
                        }
                      } catch (e) {
                        if (mounted) LoopinSnackBar.show(context, e.toString());
                      }
                    },
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.add_rounded),
                  title: const Text('Create new playlist'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const PlaylistsPage()));
                  },
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      if (mounted) LoopinSnackBar.show(context, e.toString());
    }
  }

  void _showSongActions() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (sheetContext) => SafeArea(
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.queue_music_rounded),
                title: const Text('Open queue'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showQueue();
                },
              ),
              ListTile(
                leading: const Icon(Icons.share_outlined),
                title: const Text('Share'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  LoopinSnackBar.show(context, 'Sharing is coming next in Loopin.');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

}

class _QueueSheet extends StatelessWidget {
  const _QueueSheet();

  @override
  Widget build(BuildContext context) {
    final audio = GlobalAudioService();
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * .72,
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('Up next', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                  ),
                  Text(
                    '${(audio.queue.isNotEmpty ? audio.queue.length - 1 : 0)} tracks',
                    style: const TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                ],
              ),
            ),
            Expanded(
              child: StreamBuilder<List<Song>>(
                stream: audio.queueStream,
                initialData: audio.queue,
                builder: (context, snapshot) {
                  final songs = snapshot.data ?? const <Song>[];
                  if (songs.isEmpty) {
                    return const Center(
                      child: Text('Your queue is empty', style: TextStyle(color: AppColors.muted)),
                    );
                  }
                  final currentIndex = audio.currentIndex ?? 0;
                  return ReorderableListView.builder(
                    buildDefaultDragHandles: false,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: songs.length,
                    onReorderItem: (oldIndex, newIndex) =>
                        unawaited(audio.reorderQueue(oldIndex, newIndex)),
                    itemBuilder: (context, index) {
                      final song = songs[index];
                      final active = index == currentIndex;
                      return Material(
                        key: ValueKey(song.id),
                        type: MaterialType.transparency,
                        child: ListTile(
                          selected: active,
                          selectedTileColor: AppColors.surfaceElevated,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(9),
                            child: Image.network(
                              song.imageUrl,
                              width: 50,
                              height: 50,
                              fit: BoxFit.cover,
                              filterQuality: FilterQuality.high,
                              errorBuilder: (_, __, ___) => const SizedBox(
                                width: 50,
                                height: 50,
                                child: ColoredBox(
                                  color: AppColors.surfaceElevated,
                                  child: Icon(Icons.music_note_rounded),
                                ),
                              ),
                            ),
                          ),
                          title: Text(
                            song.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: active ? AppColors.accent : Colors.white,
                              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                            ),
                          ),
                          subtitle: Text(
                            active ? 'Playing now • ${song.artist}' : song.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: active
                              ? const Icon(Icons.graphic_eq_rounded, color: AppColors.accent)
                              : ReorderableDelayedDragStartListener(
                                  index: index,
                                  child: const Padding(
                                    padding: EdgeInsets.all(8),
                                    child: Icon(Icons.drag_handle_rounded, color: Colors.white38),
                                  ),
                                ),
                          onTap: () async {
                            await audio.playAtIndex(index);
                            if (context.mounted) Navigator.pop(context);
                          },
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
