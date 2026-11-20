import 'package:flutter/material.dart';

import '../models/song.dart';
import '../services/audio_service.dart';
import '../services/monochrome_api.dart';
import '../services/service_config_service.dart';
import '../theme/app_theme.dart';
import 'music_player_page.dart';
import 'debug_console_page.dart';
import '../widgets/loopin_snackbar.dart';

class DiscoverPage extends StatefulWidget {
  final String? initialQuery;

  const DiscoverPage({super.key, this.initialQuery});

  @override
  State<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends State<DiscoverPage> {
  final _controller = TextEditingController();
  final _api = MonochromeApi();
  final _audio = GlobalAudioService();
  final _services = ServiceConfigService();

  List<Song> _songs = const [];
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _nextPage = 3;
  String? _error;
  String? _openingId;
  int _searchGeneration = 0;

  static const _quickSearches = [
    'Malayalam hits',
    'A. R. Rahman',
    'Anirudh',
    'Vineeth Sreenivasan',
    'lofi',
    'romantic songs',
  ];

  @override
  void initState() {
    super.initState();
    _controller.text = widget.initialQuery ?? '';
    if (_controller.text.trim().isNotEmpty) {
      _load(_controller.text);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load(String query) async {
    final generation = ++_searchGeneration;
    final clean = query.trim();
    if (clean.isEmpty) {
      if (!mounted) return;
      setState(() {
        _songs = const [];
        _error = null;
        _loading = false;
        _loadingMore = false;
        _hasMore = false;
        _nextPage = 1;
      });
      return;
    }

    setState(() {
      _loading = true;
      _loadingMore = false;
      _error = null;
      _hasMore = false;
    });

    if (!await _services.enabled('search')) {
      if (!mounted || generation != _searchGeneration) return;
      final message = await _services.message('search');
      if (mounted && generation == _searchGeneration) {
        setState(() {
          _songs = const [];
          _loading = false;
          _error = message;
        });
      }
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();

    try {
      // Android and web use the same catalog search contract and two-page
      // result window. Ignore responses from an older query.
      final songs = await _api.search(clean, pages: 2);
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _songs = songs;
        _nextPage = 3;
        _hasMore = songs.isNotEmpty;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _songs = const [];
        _loading = false;
        _error = 'We couldn’t load music right now.';
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _controller.text.trim().isEmpty) return;
    final generation = _searchGeneration;
    final query = _controller.text.trim();
    setState(() => _loadingMore = true);
    try {
      final page = await _api.searchPage(
        query,
        page: _nextPage,
        limit: 20,
      );
      if (!mounted || generation != _searchGeneration) return;
      if (query != _controller.text.trim()) {
        setState(() => _loadingMore = false);
        return;
      }
      final existing = _songs.map((song) => song.id).toSet();
      final fresh = page.where((song) => existing.add(song.id)).toList();
      setState(() {
        _songs = [..._songs, ...fresh];
        _nextPage++;
        _hasMore = page.length >= 20 && fresh.isNotEmpty;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted && generation == _searchGeneration) setState(() => _loadingMore = false);
    }
  }

  Future<void> _play(Song song) async {
    setState(() => _openingId = song.id);
    // Search results are discovery input, not a playlist. Let the backend
    // build Up Next from listening history, top repeats and track metadata.
    _audio.playSong(song).catchError((e) {
      if (mounted) {
        final msg = e
            .toString()
            .replaceFirst('Bad state: ', '')
            .replaceFirst('Exception: ', '');
        LoopinSnackBar.show(
          context,
          msg.isNotEmpty ? msg : 'This track could not be played. Try another one.',
          type: LoopinSnackBarType.error,
        );
      }
    });

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MusicPlayerPage(initialSong: song),
      ),
    );

    if (mounted) setState(() => _openingId = null);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Discover'),
        actions: [
          IconButton(
            tooltip: 'Diagnostics',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DebugConsolePage()),
            ),
            icon: const Icon(Icons.bug_report_outlined),
          ),
          IconButton(
            tooltip: 'Queue',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MusicPlayerPage()),
            ),
            icon: const Icon(Icons.queue_music_rounded),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isDesktop = constraints.maxWidth >= 900;
          final isWide = constraints.maxWidth >= 1350;
          final columns = isWide ? 3 : (constraints.maxWidth >= 720 ? 2 : 1);
          final horizontalPadding = isDesktop ? 32.0 : 20.0;

          return RefreshIndicator(
            onRefresh: () => _load(_controller.text),
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(child: _hero(horizontalPadding)),
                SliverToBoxAdapter(child: _searchBox(horizontalPadding, isDesktop)),
                if (_controller.text.trim().isEmpty && !_loading)
                  SliverToBoxAdapter(child: _quickSearchSection(horizontalPadding)),
                if (_loading)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_error != null)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _emptyState(
                      icon: Icons.cloud_off_rounded,
                      title: 'Nothing loaded',
                      message: _error!,
                      action: 'View diagnostics',
                      onAction: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const DebugConsolePage()),
                      ),
                    ),
                  )
                else if (_songs.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _emptyState(
                      icon: Icons.music_note_rounded,
                      title: 'Find your next repeat',
                      message:
                          'Search for a song, artist or album and build your listening queue.',
                    ),
                  )
                else if (columns > 1)
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(horizontalPadding, 8, horizontalPadding, 20),
                    sliver: SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        mainAxisExtent: 84,
                        crossAxisSpacing: 14,
                        mainAxisSpacing: 12,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => _songTile(_songs[index], index),
                        childCount: _songs.length,
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(horizontalPadding, 8, horizontalPadding, 20),
                    sliver: SliverList.separated(
                      itemCount: _songs.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, index) => _songTile(_songs[index], index),
                    ),
                  ),
                if (_hasMore)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(horizontalPadding, 12, horizontalPadding, 120),
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
                            label: Text(
                              _loadingMore ? 'Loading more…' : 'Load more songs',
                            ),
                          ),
                        ),
                      ),
                    ),
                  )
                else
                  const SliverToBoxAdapter(child: SizedBox(height: 120)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _hero(double horizontalPadding) {
    return Padding(
      padding: EdgeInsets.fromLTRB(horizontalPadding, 8, horizontalPadding, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'What do you want to hear?',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          const Text(
            'Explore songs, artists and albums. Tap any track to start a queue.',
            style: TextStyle(color: AppColors.muted, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _searchBox(double horizontalPadding, bool isDesktop) {
    return Padding(
      padding: EdgeInsets.fromLTRB(horizontalPadding, 0, horizontalPadding, 20),
      child: Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: isDesktop ? 650 : double.infinity,
          ),
          child: TextField(
            controller: _controller,
            textInputAction: TextInputAction.search,
            onSubmitted: _load,
            decoration: InputDecoration(
              hintText: 'Search music...',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _controller.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear',
                      onPressed: () {
                        _controller.clear();
                        _searchGeneration++;
                        setState(() {
                          _songs = const [];
                          _error = null;
                          _loading = false;
                          _loadingMore = false;
                          _hasMore = false;
                          _nextPage = 1;
                        });
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _quickSearchSection(double horizontalPadding) {
    return Padding(
      padding: EdgeInsets.fromLTRB(horizontalPadding, 0, horizontalPadding, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Try something',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _quickSearches
                .map(
                  (query) => ActionChip(
                    label: Text(query),
                    onPressed: () {
                      _controller.text = query;
                      _load(query);
                    },
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _songTile(Song song, int index) {
    final opening = _openingId == song.id;

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _play(song),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      song.imageUrl,
                      width: 64,
                      height: 64,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 64,
                        height: 64,
                        color: AppColors.surfaceElevated,
                        child: const Icon(
                          Icons.music_note_rounded,
                          color: AppColors.muted,
                        ),
                      ),
                    ),
                  ),
                  if (opening)
                    const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
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
                      style: const TextStyle(fontWeight: FontWeight.w700),
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
                    if (song.album != null && song.album!.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        song.album!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                Icons.play_circle_fill_rounded,
                color: opening ? Colors.white24 : AppColors.accent,
                size: 34,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyState({
    required IconData icon,
    required String title,
    required String message,
    String? action,
    VoidCallback? onAction,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 48, color: Colors.white24),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted, height: 1.4),
            ),
            if (action != null) ...[
              const SizedBox(height: 18),
              FilledButton(onPressed: onAction, child: Text(action)),
            ],
          ],
        ),
      ),
    );
  }
}
