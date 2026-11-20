import 'package:flutter/material.dart';

import '../models/song.dart';
import '../services/audio_service.dart';
import '../services/monochrome_api.dart';
import '../theme/app_theme.dart';
import '../services/service_config_service.dart';
import 'music_player_page.dart';
import '../widgets/loopin_snackbar.dart';

class SearchPage extends StatefulWidget {
  final String? initialQuery;

  const SearchPage({super.key, this.initialQuery});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _search = TextEditingController();
  final _api = MonochromeApi();
  final _audio = GlobalAudioService();
  final _services = ServiceConfigService();

  List<Song> _songs = const [];
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _nextPage = 3;
  String? _playingId;

  @override
  void initState() {
    super.initState();
    _search.text = widget.initialQuery ?? '';
    if (_search.text.isNotEmpty) _load(_search.text);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load(String query) async {
    if (!await _services.enabled('search')) {
      if (!mounted) return;
      final message = await _services.message('search');
      if (!mounted) return;
      LoopinSnackBar.show(context, message);
      return;
    }
    final clean = query.trim();
    if (clean.isEmpty) return;
    FocusManager.instance.primaryFocus?.unfocus();

    setState(() => _loading = true);
    try {
      final songs = await _api.search(clean, pages: 2);
      if (mounted) setState(() { _songs = songs; _nextPage = 3; _hasMore = songs.isNotEmpty; });
    } catch (_) {
      if (!mounted) return;
      LoopinSnackBar.show(context, 'Unable to load music right now.', type: LoopinSnackBarType.error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _search.text.trim().isEmpty) return;
    setState(() => _loadingMore = true);
    try {
      final page = await _api.searchPage(_search.text.trim(), page: _nextPage, limit: 20);
      if (!mounted) return;
      final existing = _songs.map((song) => song.id).toSet();
      final fresh = page.where((song) => existing.add(song.id)).toList();
      setState(() {
        _songs = [..._songs, ...fresh];
        _nextPage++;
        _hasMore = page.length >= 20 && fresh.isNotEmpty;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _play(Song song) async {
    if (_playingId != null) return;

    setState(() => _playingId = song.id);
    try {
      await _audio.playSong(song);
      if (!mounted) return;

      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const MusicPlayerPage()),
      );
    } catch (_) {
      if (!mounted) return;
      LoopinSnackBar.show(context, 'Unable to play this song right now.', type: LoopinSnackBarType.error);
    } finally {
      if (mounted) setState(() => _playingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Search')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isDesktop = constraints.maxWidth >= 900;
          final isWide = constraints.maxWidth >= 1350;
          final columns = isWide ? 3 : (constraints.maxWidth >= 720 ? 2 : 1);
          final horizontalPadding = isDesktop ? 32.0 : 16.0;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(horizontalPadding, 6, horizontalPadding, 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: isDesktop ? 650 : double.infinity,
                    ),
                    child: TextField(
                      controller: _search,
                      autofocus: widget.initialQuery == null,
                      textInputAction: TextInputAction.search,
                      onSubmitted: _load,
                      decoration: InputDecoration(
                        hintText: 'Search songs, artists, albums...',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.arrow_forward_rounded),
                          onPressed: () => _load(_search.text),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _songs.isEmpty
                        ? const Center(
                            child: Text(
                              'Search for a song, artist or album',
                              style: TextStyle(color: AppColors.muted),
                            ),
                          )
                        : CustomScrollView(
                            slivers: [
                              SliverPadding(
                                padding: EdgeInsets.fromLTRB(horizontalPadding, 4, horizontalPadding, 12),
                                sliver: columns > 1
                                    ? SliverGrid(
                                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                          crossAxisCount: columns,
                                          mainAxisExtent: 82,
                                          crossAxisSpacing: 14,
                                          mainAxisSpacing: 10,
                                        ),
                                        delegate: SliverChildBuilderDelegate(
                                          (context, index) => _songItem(_songs[index]),
                                          childCount: _songs.length,
                                        ),
                                      )
                                    : SliverList.separated(
                                        itemCount: _songs.length,
                                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                                        itemBuilder: (_, index) => _songItem(_songs[index]),
                                      ),
                              ),
                              if (_hasMore)
                                SliverToBoxAdapter(
                                  child: Padding(
                                    padding: EdgeInsets.fromLTRB(horizontalPadding, 8, horizontalPadding, 32),
                                    child: Center(
                                      child: ConstrainedBox(
                                        constraints: const BoxConstraints(maxWidth: 400),
                                        child: OutlinedButton.icon(
                                          style: OutlinedButton.styleFrom(
                                            minimumSize: const Size.fromHeight(48),
                                          ),
                                          onPressed: _loadingMore ? null : _loadMore,
                                          icon: _loadingMore
                                              ? const SizedBox(
                                                  width: 18,
                                                  height: 18,
                                                  child: CircularProgressIndicator(strokeWidth: 2),
                                                )
                                              : const Icon(Icons.expand_more_rounded),
                                          label: Text(_loadingMore ? 'Loading more…' : 'Load more songs'),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _songItem(Song song) {
    final isOpening = _playingId == song.id;
    final isBusy = _playingId != null;

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: isBusy ? null : () => _play(song),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(
                  song.imageUrl,
                  width: 58,
                  height: 58,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 58,
                    height: 58,
                    color: AppColors.surfaceElevated,
                    child: const Icon(
                      Icons.music_note_rounded,
                      color: AppColors.muted,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      song.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 44,
                height: 44,
                child: Center(
                  child: isOpening
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : Icon(
                          Icons.play_circle_fill,
                          color: isBusy ? Colors.white24 : AppColors.accent,
                          size: 34,
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
