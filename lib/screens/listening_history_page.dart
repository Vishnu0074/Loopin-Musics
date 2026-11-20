import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/library_bloc.dart';
import 'package:just_audio/just_audio.dart';
import '../models/song.dart';
import '../services/audio_service.dart';
import '../services/monochrome_api.dart';
import '../services/playlist_service.dart';
import '../theme/app_theme.dart';
import '../widgets/loopin_snackbar.dart';
import 'music_player_page.dart';

Song _historySong(Map row) {
  final metadata = row['metadata'] is Map
      ? Map<String, dynamic>.from(row['metadata'])
      : <String, dynamic>{};
  final rawMedia = metadata['media_url']?.toString() ?? '';
  // Avoid replaying temporary backend proxy URLs whose tokens may have expired
  final mediaUrl = rawMedia.contains('/catalog/music/stream/') ? '' : rawMedia;
  return Song(
    id: row['song_id']?.toString() ?? '',
    title: row['title']?.toString() ?? 'Unknown track',
    artist: row['artist']?.toString() ?? 'Unknown artist',
    album: row['album']?.toString(),
    imageUrl:
        row['image_url']?.toString() ?? metadata['image_url']?.toString() ?? '',
    mediaUrl: mediaUrl,
  );
}

class RecentListeningSection extends StatefulWidget {
  const RecentListeningSection({super.key});
  @override
  State<RecentListeningSection> createState() => _RecentListeningSectionState();
}

class _RecentListeningSectionState extends State<RecentListeningSection> {
  final _api = PlaylistService();
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  StreamSubscription<int?>? _trackSubscription;
  @override
  void initState() {
    super.initState();
    _load();
    _trackSubscription = GlobalAudioService().currentIndexStream.listen((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    try {
      final data = await _api.historyPage(page: 1, pageSize: 12);
      final rows = (data['items'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      if (mounted) setState(() => _items = rows);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _trackSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final pad = width >= 900 ? 32.0 : 20.0;
    if (_loading) {
      return SizedBox(
        height: 196,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.symmetric(horizontal: pad),
          itemCount: 4,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (_, __) => Container(
            width: 140,
            height: 196,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white10),
            ),
            child: const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.accent,
                ),
              ),
            ),
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: pad, vertical: 12),
        child: const Text(
          'Songs you play will show up here.',
          style: TextStyle(color: AppColors.muted),
        ),
      );
    }
    return SizedBox(
      height: 196,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: pad),
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final song = _historySong(_items[index]);
          return _RecentPlayedCard(song: song);
        },
      ),
    );
  }
}

class ListeningHistoryPage extends StatefulWidget {
  const ListeningHistoryPage({super.key});
  @override
  State<ListeningHistoryPage> createState() => _ListeningHistoryPageState();
}

class _ListeningHistoryPageState extends State<ListeningHistoryPage> {
  final _api = PlaylistService();
  final _scroll = ScrollController();
  final List<Map<String, dynamic>> _items = [];
  int _page = 1;
  bool _hasNext = true;
  bool _loading = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _loadNext();
  }

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 420) {
      _loadNext();
    }
  }

  Future<void> _loadNext({bool reset = false}) async {
    if (_loading || (!_hasNext && !reset)) return;
    if (reset) {
      _page = 1;
      _hasNext = true;
      _items.clear();
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _api.historyPage(page: _page, pageSize: 25);
      final rows = (data['items'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      if (!mounted) return;
      setState(() {
        _items.addAll(rows);
        _hasNext = data['has_next'] == true;
        _page++;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Listening history')),
    body: RefreshIndicator(
      onRefresh: () => _loadNext(reset: true),
      child: ListView.builder(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: _items.length + (_loading || _error != null ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _items.length) {
            if (_error != null) {
              return TextButton(
                onPressed: _loadNext,
                child: Text('Could not load more. Retry'),
              );
            }
            return const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _HistorySongCard(song: _historySong(_items[index])),
          );
        },
      ),
    ),
  );
}

class _HistorySongCard extends StatefulWidget {
  final Song song;
  const _HistorySongCard({required this.song});
  @override
  State<_HistorySongCard> createState() => _HistorySongCardState();
}

class _HistorySongCardState extends State<_HistorySongCard> {
  final _resolver = MonochromeApi();
  AudioPlayer? _preview;
  bool _previewing = false;
  bool _busy = false;

  Future<void> _startPreview() async {
    if (_previewing || _busy) return;
    setState(() {
      _busy = true;
    });
    try {
      final player = AudioPlayer();
      _preview = player;
      final url = await _resolver.resolveStream(widget.song);
      if (url == null || url.isEmpty) throw Exception('Preview unavailable');
      if (!mounted || !identical(_preview, player)) {
        await player.dispose();
        return;
      }
      await player.setUrl(url);
      if (!mounted || !identical(_preview, player)) {
        await player.dispose();
        return;
      }
      if (mounted) setState(() => _previewing = true);
      unawaited(player.play());
    } catch (e) {
      if (mounted) LoopinSnackBar.show(context, e.toString());
      await _stopPreview();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stopPreview() async {
    final player = _preview;
    _preview = null;
    if (mounted) setState(() => _previewing = false);
    if (player != null) {
      await player.stop();
      await player.dispose();
    }
  }

  Future<void> _like() async {
    try {
      context.read<LibraryBloc>().add(LikeToggled(widget.song));
      if (mounted) LoopinSnackBar.show(context, 'Liked songs updated');
    } catch (e) {
      if (mounted) LoopinSnackBar.show(context, e.toString());
    }
  }

  Future<void> _addToPlaylist() async {
    try {
      final playlists = context.read<LibraryBloc>().state.playlists;
      if (!mounted) return;
      final selected = await showModalBottomSheet<dynamic>(
        context: context,
        backgroundColor: AppColors.surface,
        builder: (ctx) => SafeArea(
          child: SizedBox(
            height: 360,
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Add to playlist',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
                Expanded(
                  child: ListView(
                    children: playlists
                        .where((p) => p.owner == null || !p.isPublic)
                        .map(
                          (p) => ListTile(
                            leading: const Icon(Icons.queue_music_rounded),
                            title: Text(p.name),
                            onTap: () => Navigator.pop(ctx, p.id),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      if (!mounted || selected == null) return;
      context.read<LibraryBloc>().add(
        PlaylistSongAdded(selected as int, widget.song),
      );
      LoopinSnackBar.show(context, 'Added to playlist');
    } catch (e) {
      if (mounted) LoopinSnackBar.show(context, e.toString());
    }
  }

  Future<void> _play() async {
    await _stopPreview();
    final song = widget.song;
    unawaited(GlobalAudioService().playSong(song).catchError((e) {
      if (mounted) LoopinSnackBar.show(context, 'Playback error: $e');
    }));
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MusicPlayerPage(initialSong: song),
      ),
    );
  }

  @override
  void dispose() {
    final p = _preview;
    if (p != null) unawaited(p.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final song = widget.song;
    return GestureDetector(
      onLongPressStart: (_) => _startPreview(),
      onLongPressEnd: (_) => _stopPreview(),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.divider),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _play,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: song.imageUrl.isEmpty
                      ? Container(
                          width: 52,
                          height: 52,
                          color: AppColors.surfaceElevated,
                          child: const Icon(Icons.music_note, color: AppColors.muted),
                        )
                      : Image.network(
                          song.imageUrl,
                          width: 52,
                          height: 52,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 52,
                            height: 52,
                            color: AppColors.surfaceElevated,
                            child: const Icon(Icons.music_note, color: AppColors.muted),
                          ),
                        ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        song.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 12,
                        ),
                      ),
                      if (_previewing)
                        const Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Text(
                            'PREVIEWING · release to stop',
                            style: TextStyle(
                              color: AppColors.accent,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Like',
                  onPressed: _like,
                  icon: const Icon(Icons.favorite_border_rounded, size: 20),
                ),
                IconButton(
                  tooltip: 'Add to playlist',
                  onPressed: _addToPlaylist,
                  icon: const Icon(Icons.playlist_add_rounded, size: 22),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RecentPlayedCard extends StatefulWidget {
  final Song song;
  const _RecentPlayedCard({required this.song});

  @override
  State<_RecentPlayedCard> createState() => _RecentPlayedCardState();
}

class _RecentPlayedCardState extends State<_RecentPlayedCard> {
  final _audio = GlobalAudioService();
  final _resolver = MonochromeApi();
  AudioPlayer? _preview;
  bool _previewing = false;
  bool _busy = false;

  Future<void> _startPreview() async {
    if (_previewing || _busy) return;
    setState(() => _busy = true);
    try {
      final player = AudioPlayer();
      _preview = player;
      final url = await _resolver.resolveStream(widget.song);
      if (url == null || url.isEmpty) throw Exception('Preview unavailable');
      if (!mounted || !identical(_preview, player)) {
        await player.dispose();
        return;
      }
      await player.setUrl(url);
      if (!mounted || !identical(_preview, player)) {
        await player.dispose();
        return;
      }
      if (mounted) setState(() => _previewing = true);
      unawaited(player.play());
    } catch (e) {
      if (mounted) LoopinSnackBar.show(context, e.toString());
      await _stopPreview();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stopPreview() async {
    final player = _preview;
    _preview = null;
    if (mounted) setState(() => _previewing = false);
    if (player != null) {
      await player.stop();
      await player.dispose();
    }
  }

  Future<void> _play() async {
    _audio.playSong(widget.song).catchError((e) {
      if (mounted) LoopinSnackBar.show(context, 'Playback error: $e');
    });
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MusicPlayerPage(initialSong: widget.song),
      ),
    );
  }

  Future<void> _like() async {
    try {
      context.read<LibraryBloc>().add(LikeToggled(widget.song));
      if (mounted) LoopinSnackBar.show(context, 'Liked songs updated');
    } catch (e) {
      if (mounted) LoopinSnackBar.show(context, e.toString());
    }
  }

  @override
  void dispose() {
    final p = _preview;
    if (p != null) unawaited(p.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final song = widget.song;

    return SizedBox(
      width: 140,
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _play,
          onLongPress: _startPreview,
          borderRadius: BorderRadius.circular(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Cover Artwork
              Stack(
                children: [
                  SizedBox(
                    width: 140,
                    height: 136,
                    child: song.imageUrl.isNotEmpty
                        ? Image.network(
                            song.imageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _coverPlaceholder(),
                          )
                        : _coverPlaceholder(),
                  ),
                  // Dark subtle gradient overlay at bottom
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.4),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Floating quick like button at top right
                  Positioned(
                    top: 6,
                    right: 6,
                    child: GestureDetector(
                      onTap: _like,
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.favorite_border_rounded,
                          color: Colors.white70,
                          size: 15,
                        ),
                      ),
                    ),
                  ),
                  // Floating play button at bottom right
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black.withValues(alpha: 0.7),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.15),
                          width: 1,
                        ),
                      ),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                  // Previewing pulse overlay
                  if (_previewing)
                    Positioned.fill(
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.75),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(
                              Icons.graphic_eq_rounded,
                              color: AppColors.accent,
                              size: 26,
                            ),
                            SizedBox(height: 4),
                            Text(
                              'PREVIEWING',
                              style: TextStyle(
                                color: AppColors.accent,
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              // Track Title & Artist Info
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 3),
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
    );
  }

  Widget _coverPlaceholder() {
    return Container(
      color: AppColors.surfaceElevated,
      alignment: Alignment.center,
      child: const Icon(
        Icons.music_note_rounded,
        color: AppColors.muted,
        size: 32,
      ),
    );
  }
}
