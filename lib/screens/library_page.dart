import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/library_bloc.dart';
import '../models/song.dart';
import '../services/audio_service.dart';
import '../theme/app_theme.dart';
import 'music_player_page.dart';
import 'playlists_page.dart';
import '../widgets/loopin_snackbar.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});
  @override State<LibraryPage> createState() => _LibraryPageState();
}
class _LibraryPageState extends State<LibraryPage> {
  List<Song> get _liked => context.watch<LibraryBloc>().state.likedSongs;
  bool get _loadingLikes => context.watch<LibraryBloc>().state.loading;
  Future<void> _loadLikes() async { context.read<LibraryBloc>().add(const LibraryRefreshed()); }
  Future<void> _play(Song song) async {
    try {
      await GlobalAudioService().playSong(song);
      if (!mounted) return;
      Navigator.push(context, MaterialPageRoute(builder: (_) => const MusicPlayerPage()));
    } catch (error) {
      if (mounted) LoopinSnackBar.show(context, error.toString());
    }
  }
  @override
  Widget build(BuildContext context) {
    final audio = GlobalAudioService();
    return BlocBuilder<LibraryBloc, LibraryState>(
      builder: (context, libraryState) => Scaffold(
      appBar: AppBar(title: const Text('Your library')),
      body: RefreshIndicator(
        onRefresh: _loadLikes,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isDesktop = constraints.maxWidth >= 900;

            if (isDesktop) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(28, 12, 28, 32),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 6,
                      child: ListView(
                        padding: const EdgeInsets.only(right: 12),
                        children: [
                          _playlistsSection(),
                          const SizedBox(height: 24),
                          _likedSongsHeader(),
                          const SizedBox(height: 10),
                          _likedSongsContent(),
                        ],
                      ),
                    ),
                    const VerticalDivider(width: 24, thickness: 1, color: AppColors.divider),
                    Expanded(
                      flex: 5,
                      child: ListView(
                        padding: const EdgeInsets.only(left: 12),
                        children: [
                          _queueHeader(audio),
                          const SizedBox(height: 10),
                          _queueContent(audio),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 140),
              children: [
                _playlistsSection(),
                const SizedBox(height: 24),
                _likedSongsHeader(),
                const SizedBox(height: 10),
                _likedSongsContent(),
                const SizedBox(height: 28),
                _queueHeader(audio),
                const SizedBox(height: 10),
                _queueContent(audio),
              ],
            );
          },
        ),
      ),
    ),
    );
  }

  Widget _playlistsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Playlists',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PlaylistsPage()),
              ),
              child: const Text('Open all'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Card(
          color: AppColors.surface,
          child: ListTile(
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.queue_music_rounded, color: AppColors.accent),
            ),
            title: const Text('Your playlists', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: const Text('Create, reorder and build playlists from search, likes and recent plays.'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PlaylistsPage()),
            ),
          ),
        ),
      ],
    );
  }

  Widget _likedSongsHeader() {
    return Row(
      children: [
        const Expanded(
          child: Text(
            'Liked songs',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
        ),
        if (_liked.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${_liked.length} tracks',
              style: const TextStyle(
                color: AppColors.accent,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
      ],
    );
  }

  Widget _likedSongsContent() {
    if (_loadingLikes) {
      return const Padding(
        padding: EdgeInsets.all(28),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_liked.isEmpty) {
      return const Card(
        color: AppColors.surface,
        child: ListTile(
          leading: Icon(Icons.favorite_border_rounded),
          title: Text('No liked songs yet'),
          subtitle: Text('Like a song and it will stay in your library.'),
        ),
      );
    }
    return Column(
      children: _liked.map((song) => Card(
        color: AppColors.surface,
        child: ListTile(
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: Image.network(
              song.imageUrl,
              width: 52,
              height: 52,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const SizedBox(
                width: 52,
                height: 52,
                child: ColoredBox(
                  color: AppColors.surfaceElevated,
                  child: Icon(Icons.music_note_rounded),
                ),
              ),
            ),
          ),
          title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(song.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: IconButton(
            tooltip: 'Remove from liked songs',
            icon: const Icon(Icons.favorite_rounded, color: AppColors.accent),
            onPressed: () => context.read<LibraryBloc>().add(LikeToggled(song)),
          ),
          onTap: () => _play(song),
        ),
      )).toList(),
    );
  }

  Widget _queueHeader(GlobalAudioService audio) {
    return StreamBuilder<List<Song>>(
      stream: audio.queueStream,
      initialData: audio.queue,
      builder: (context, snapshot) {
        final count = (snapshot.data ?? const <Song>[]).length;
        return Row(
          children: [
            const Expanded(
              child: Text(
                'Current queue',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              ),
            ),
            if (count > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$count queued',
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _queueContent(GlobalAudioService audio) {
    return StreamBuilder<List<Song>>(
      stream: audio.queueStream,
      initialData: audio.queue,
      builder: (context, snapshot) {
        final songs = snapshot.data ?? const <Song>[];
        if (songs.isEmpty) {
          return const Card(
            color: AppColors.surface,
            child: ListTile(
              leading: Icon(Icons.queue_music_rounded),
              title: Text('Your queue is empty'),
              subtitle: Text('Play any song to start your queue.'),
            ),
          );
        }
        return StreamBuilder<int?>(
          stream: audio.currentIndexStream,
          initialData: audio.currentIndex,
          builder: (context, indexSnap) {
            final activeIndex = indexSnap.data ?? audio.currentIndex;
            return Column(
              children: songs.asMap().entries.map((entry) {
                final index = entry.key;
                final song = entry.value;
                final active = index == activeIndex;
                return Card(
                  color: active ? AppColors.surfaceElevated : AppColors.surface,
                  child: ListTile(
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(9),
                      child: Image.network(
                        song.imageUrl,
                        width: 52,
                        height: 52,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox(
                          width: 52,
                          height: 52,
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
                        fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                        color: active ? AppColors.accent : Colors.white,
                      ),
                    ),
                    subtitle: Text(song.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: Icon(
                      active ? Icons.graphic_eq_rounded : Icons.play_arrow_rounded,
                      color: active ? AppColors.accent : AppColors.muted,
                    ),
                    onTap: () async {
                      await audio.playAtIndex(index);
                    },
                  ),
                );
              }).toList(),
            );
          },
        );
      },
    );
  }
}
