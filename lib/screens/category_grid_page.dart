import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import '../models/song.dart';
import '../services/audio_service.dart';
import '../services/monochrome_api.dart';
import '../services/service_config_service.dart';
import '../services/track_normalizer.dart';
import '../theme/app_theme.dart';
import 'music_player_page.dart';
import '../widgets/loopin_snackbar.dart';

enum CategoryLayoutMode {
  mosaic, // Instagram Explore asymmetrical quilted layout
  waterfall, // Masonry dynamic staggered heights
  grid, // Classic uniform 2-column
}

class CategoryGridPage extends StatefulWidget {
  final String title;
  final String query;
  final String? subtitle;
  final String? bannerImageUrl;

  const CategoryGridPage({
    super.key,
    required this.title,
    required this.query,
    this.subtitle,
    this.bannerImageUrl,
  });

  @override
  State<CategoryGridPage> createState() => _CategoryGridPageState();
}

class _CategoryGridPageState extends State<CategoryGridPage> {
  final _api = MonochromeApi();
  final _audio = GlobalAudioService();
  final _services = ServiceConfigService();
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();

  List<Song> _songs = const [];
  List<Song> _filteredSongs = const [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _currentPage = 1;
  String? _error;
  String? _openingSongId;
  CategoryLayoutMode _layoutMode = CategoryLayoutMode.mosaic;

  @override
  void initState() {
    super.initState();
    _loadInitial();
    _scrollController.addListener(_onScroll);
    _searchController.addListener(_onFilterChanged);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.extentAfter < 350 &&
        !_loading &&
        !_loadingMore &&
        _hasMore) {
      _loadMore();
    }
  }

  void _onFilterChanged() {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      setState(() {
        _filteredSongs = _songs;
      });
      return;
    }

    setState(() {
      _filteredSongs = _songs.where((song) {
        final title = song.title.toLowerCase();
        final artist = song.artist.toLowerCase();
        final album = (song.album ?? '').toLowerCase();
        return title.contains(query) ||
            artist.contains(query) ||
            album.contains(query);
      }).toList();
    });
  }

  Future<void> _loadInitial() async {
    setState(() {
      _loading = true;
      _error = null;
      _currentPage = 1;
    });

    if (!await _services.enabled('search')) {
      final msg = await _services.message('search');
      if (mounted) {
        setState(() {
          _loading = false;
          _error = msg;
        });
      }
      return;
    }

    try {
      final results = await _api.searchPage(widget.query, page: 1, limit: 30);
      final deduplicated = _deduplicate(results);
      if (mounted) {
        setState(() {
          _songs = deduplicated;
          _filteredSongs = deduplicated;
          _loading = false;
          _hasMore = results.length >= 20;
          _currentPage = 1;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Failed to load category tracks. Please try again.';
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);

    try {
      final nextPage = _currentPage + 1;
      final results = await _api.searchPage(
        widget.query,
        page: nextPage,
        limit: 30,
      );
      if (results.isEmpty) {
        if (mounted) setState(() => _hasMore = false);
      } else {
        final combined = _deduplicate([..._songs, ...results]);
        if (mounted) {
          setState(() {
            _songs = combined;
            _onFilterChanged();
            _currentPage = nextPage;
            _hasMore = results.length >= 15;
          });
        }
      }
    } catch (_) {
      if (mounted) setState(() => _hasMore = false);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  List<Song> _deduplicate(List<Song> list) {
    final result = <Song>[];
    for (final song in list) {
      if (song.id.isEmpty || song.title.isEmpty) continue;
      if (!result.any(
        (existing) => TrackNormalizer.isDuplicate(existing, song),
      )) {
        result.add(song);
      }
    }
    return result;
  }

  Future<void> _playSong(
    Song song, {
    bool openPlayer = false,
    List<Song>? customContext,
  }) async {
    setState(() => _openingSongId = song.id);
    final contextList = customContext ?? _filteredSongs;

    if (openPlayer && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => MusicPlayerPage(initialSong: song)),
      );
    }

    try {
      await _audio.playSong(song, context: contextList);
    } catch (e) {
      if (mounted) {
        LoopinSnackBar.show(context, 'Playback error: ${e.toString()}');
      }
    } finally {
      if (mounted) {
        setState(() => _openingSongId = null);
      }
    }
  }

  Future<void> _playAll({bool shuffle = false}) async {
    if (_filteredSongs.isEmpty) return;
    final list = List<Song>.from(_filteredSongs);
    if (shuffle) {
      list.shuffle();
      if (mounted) {
        LoopinSnackBar.show(
          context,
          'Shuffling \${widget.title} queue (\${list.length} tracks)',
          duration: const Duration(seconds: 2),
        );
      }
    } else {
      if (mounted) {
        LoopinSnackBar.show(
          context,
          'Playing \${widget.title} queue (\${list.length} tracks)',
          duration: const Duration(seconds: 2),
        );
      }
    }
    await _playSong(list.first, openPlayer: true, customContext: list);
  }

  String _formatDuration(int? seconds) {
    if (seconds == null || seconds <= 0) return '';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _loadInitial,
          color: AppColors.accent,
          backgroundColor: AppColors.surfaceElevated,
          child: CustomScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              _sliverHeader(),
              SliverToBoxAdapter(child: _filterAndActionRow()),
              if (_loading)
                _skeletonGrid()
              else if (_error != null)
                SliverFillRemaining(hasScrollBody: false, child: _errorWidget())
              else if (_filteredSongs.isEmpty)
                SliverFillRemaining(hasScrollBody: false, child: _emptyWidget())
              else ...[
                _songGrid(),
                if (_loadingMore)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: CircularProgressIndicator(
                          color: AppColors.accent,
                          strokeWidth: 2.5,
                        ),
                      ),
                    ),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 100)),
              ],
            ],
          ),
        ),
      ),
      bottomSheet: _nowPlayingBar(),
    );
  }

  int _mosaicColumns(double width) {
    if (width >= 1400) return 6;
    if (width >= 1000) return 5;
    if (width >= 650) return 4;
    return 3;
  }

  List<QuiltedGridTile> _mosaicPattern(int cols) {
    if (cols == 6) {
      return const [
        QuiltedGridTile(2, 2),
        QuiltedGridTile(1, 1),
        QuiltedGridTile(1, 1),
        QuiltedGridTile(1, 1),
        QuiltedGridTile(1, 1),
        QuiltedGridTile(1, 1),
        QuiltedGridTile(1, 1),
        QuiltedGridTile(1, 1),
        QuiltedGridTile(1, 1),
        QuiltedGridTile(1, 1),
      ];
    }
    if (cols == 5) {
      return const [
        QuiltedGridTile(2, 2),
        QuiltedGridTile(1, 1),
        QuiltedGridTile(1, 1),
        QuiltedGridTile(1, 1),
        QuiltedGridTile(1, 1),
        QuiltedGridTile(1, 1),
        QuiltedGridTile(1, 1),
        QuiltedGridTile(1, 1),
      ];
    }
    if (cols == 4) {
      return const [
        QuiltedGridTile(2, 2),
        QuiltedGridTile(1, 1),
        QuiltedGridTile(1, 1),
        QuiltedGridTile(1, 1),
        QuiltedGridTile(1, 1),
        QuiltedGridTile(1, 1),
      ];
    }
    return const [
      QuiltedGridTile(2, 2),
      QuiltedGridTile(1, 1),
      QuiltedGridTile(1, 1),
      QuiltedGridTile(1, 1),
      QuiltedGridTile(1, 1),
      QuiltedGridTile(1, 1),
    ];
  }

  int _waterfallColumns(double width) {
    if (width >= 1400) return 5;
    if (width >= 1000) return 4;
    if (width >= 650) return 3;
    return 2;
  }

  int _gridColumns(double width) {
    if (width >= 1400) return 5;
    if (width >= 1000) return 4;
    if (width >= 650) return 3;
    return 2;
  }

  double _horizontalPadding(double width) {
    if (width >= 1400) return 36.0;
    if (width >= 900) return 24.0;
    return 12.0;
  }

  Widget _sliverHeader() {
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = width >= 900;
    final heroImage =
        widget.bannerImageUrl ??
        (_songs.isNotEmpty ? _songs.first.imageUrl : '');

    return SliverAppBar(
      expandedHeight: isDesktop ? 280 : 230,
      pinned: true,
      backgroundColor: AppColors.background,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      leading: IconButton(
        icon: Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white12),
          ),
          child: const Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 16,
            color: Colors.white,
          ),
        ),
        onPressed: () => Navigator.pop(context),
      ),
      actions: [
        IconButton(
          icon: Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white12),
            ),
            child: const Icon(
              Icons.shuffle_rounded,
              size: 18,
              color: Colors.white,
            ),
          ),
          tooltip: 'Shuffle Play',
          onPressed: () => _playAll(shuffle: true),
        ),
        const SizedBox(width: 8),
      ],
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: EdgeInsets.fromLTRB(
          isDesktop ? 32 : 20,
          0,
          isDesktop ? 32 : 20,
          isDesktop ? 22 : 16,
        ),
        title: Text(
          widget.title,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: isDesktop ? 45 : 25,
            shadows: const [Shadow(color: Colors.black, blurRadius: 10)],
          ),
        ),
        background: Stack(
          fit: StackFit.expand,
          children: [
            if (heroImage.isNotEmpty)
              Image.network(
                heroImage,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    Container(color: AppColors.surface),
              )
            else
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF2C1034),
                      Color(0xFF0F0B18),
                      AppColors.background,
                    ],
                  ),
                ),
              ),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.3),
                    Colors.transparent,
                    AppColors.background.withValues(alpha: 0.85),
                    AppColors.background,
                  ],
                  stops: const [0.0, 0.35, 0.8, 1.0],
                ),
              ),
            ),
            // Positioned(
            //   left: 20,
            //   bottom: 48,
            //   right: 20,
            //   child: Column(
            //     crossAxisAlignment: CrossAxisAlignment.start,
            //     mainAxisSize: MainAxisSize.min,
            //     children: [
            //       Container(
            //         padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            //         decoration: BoxDecoration(
            //           color: AppColors.accent.withOpacity(0.2),
            //           borderRadius: BorderRadius.circular(12),
            //           border: Border.all(color: AppColors.accent.withOpacity(0.5)),
            //         ),
            //         child: Text(
            //           widget.subtitle ?? 'FEATURED CATEGORY',
            //           style: const TextStyle(
            //             color: AppColors.accent,
            //             fontSize: 10,
            //             fontWeight: FontWeight.w800,
            //             letterSpacing: 1.2,
            //           ),
            //         ),
            //       ),
            //     ],
            //   ),
            // ),
          ],
        ),
      ),
    );
  }

  Widget _filterAndActionRow() {
    final width = MediaQuery.sizeOf(context).width;
    final hPad = _horizontalPadding(width);
    return Padding(
      padding: EdgeInsets.fromLTRB(hPad, 8, hPad, 16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Filter in ${widget.title}...',
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      size: 20,
                      color: AppColors.muted,
                    ),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 18),
                            onPressed: () => _searchController.clear(),
                          )
                        : null,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    filled: true,
                    fillColor: AppColors.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: Colors.white10),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: Colors.white10),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: AppColors.accent),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: () => _playAll(shuffle: false),
                icon: const Icon(Icons.play_arrow_rounded, size: 22),
                label: const Text(
                  'Play',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                '${_filteredSongs.length} Tracks',
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              // Layout Selector Glass Pill
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _layoutButton(
                      mode: CategoryLayoutMode.mosaic,
                      icon: Icons.auto_awesome_mosaic_rounded,
                      tooltip: 'Explore Mosaic',
                    ),
                    _layoutButton(
                      mode: CategoryLayoutMode.waterfall,
                      icon: Icons.view_quilt_rounded,
                      tooltip: 'Waterfall Staggered',
                    ),
                    _layoutButton(
                      mode: CategoryLayoutMode.grid,
                      icon: Icons.grid_view_rounded,
                      tooltip: 'Classic Grid',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _layoutButton({
    required CategoryLayoutMode mode,
    required IconData icon,
    required String tooltip,
  }) {
    final isSelected = _layoutMode == mode;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: () => setState(() => _layoutMode = mode),
        borderRadius: BorderRadius.circular(9),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(
            icon,
            size: 16,
            color: isSelected ? Colors.white : AppColors.muted,
          ),
        ),
      ),
    );
  }

  Widget _songGrid() {
    final width = MediaQuery.sizeOf(context).width;
    final hPad = _horizontalPadding(width);

    switch (_layoutMode) {
      case CategoryLayoutMode.mosaic:
        final cols = _mosaicColumns(width);
        final pattern = _mosaicPattern(cols);
        return SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: hPad),
          sliver: SliverGrid(
            gridDelegate: SliverQuiltedGridDelegate(
              crossAxisCount: cols,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              repeatPattern: QuiltedGridRepeatPattern.inverted,
              pattern: pattern,
            ),
            delegate: SliverChildBuilderDelegate((context, index) {
              final song = _filteredSongs[index];
              final isBig = (index % pattern.length == 0);
              return _reelsCard(song, index, isBig: isBig);
            }, childCount: _filteredSongs.length),
          ),
        );

      case CategoryLayoutMode.waterfall:
        final cols = _waterfallColumns(width);
        return SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: hPad),
          sliver: SliverMasonryGrid.count(
            crossAxisCount: cols,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            itemBuilder: (context, index) {
              final song = _filteredSongs[index];
              final isTall = (index % 3 == 0) || (index % 5 == 1);
              return _reelsCard(song, index, isTall: isTall);
            },
            childCount: _filteredSongs.length,
          ),
        );

      case CategoryLayoutMode.grid:
        final cols = _gridColumns(width);
        return SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: hPad),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: 0.74,
            ),
            delegate: SliverChildBuilderDelegate((context, index) {
              final song = _filteredSongs[index];
              return _reelsCard(song, index);
            }, childCount: _filteredSongs.length),
          ),
        );
    }
  }

  Widget _reelsCard(
    Song song,
    int index, {
    bool isBig = false,
    bool isTall = false,
  }) {
    final isOpening = _openingSongId == song.id;
    final cardContent = StreamBuilder<List<Song>>(
      stream: _audio.queueStream,
      initialData: _audio.queue,
      builder: (context, queueSnap) {
        return StreamBuilder<int?>(
          stream: _audio.currentIndexStream,
          initialData: _audio.currentIndex,
          builder: (context, idxSnap) {
            final queue = queueSnap.data ?? const <Song>[];
            final currentIndex = idxSnap.data;
            final isPlayingThis =
                currentIndex != null &&
                currentIndex >= 0 &&
                currentIndex < queue.length &&
                TrackNormalizer.isDuplicate(queue[currentIndex], song);

            return Material(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(isBig ? 24 : 18),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => _playSong(song, openPlayer: true),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Artwork Background
                    Image.network(
                      song.imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: AppColors.surfaceElevated,
                        child: Icon(
                          Icons.music_note_rounded,
                          size: isBig ? 64 : 36,
                          color: AppColors.muted,
                        ),
                      ),
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return Container(color: AppColors.surfaceElevated);
                      },
                    ),

                    // Modern Multi-Stop Gradient
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.15),
                            Colors.transparent,
                            Colors.black.withValues(alpha: isBig ? 0.65 : 0.75),
                            Colors.black.withValues(alpha: 0.95),
                          ],
                          stops: const [0.0, 0.35, 0.7, 1.0],
                        ),
                      ),
                    ),

                    // Active border glow
                    if (isPlayingThis)
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(isBig ? 24 : 18),
                          border: Border.all(
                            color: AppColors.accent,
                            width: isBig ? 3.0 : 2.5,
                          ),
                        ),
                      ),

                    // Top Indicators
                    Positioned(
                      top: isBig ? 12 : 8,
                      left: isBig ? 12 : 8,
                      right: isBig ? 12 : 8,
                      child: Row(
                        children: [
                          if (isBig)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.7),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: AppColors.accent.withValues(
                                    alpha: 0.4,
                                  ),
                                ),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.star_rounded,
                                    size: 12,
                                    color: Colors.amber,
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    'FEATURED',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else if (song.durationSeconds != null &&
                              song.durationSeconds! > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.65),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.white10),
                              ),
                              child: Text(
                                _formatDuration(song.durationSeconds),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          const Spacer(),
                          if (isPlayingThis)
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: isBig ? 8 : 6,
                                vertical: isBig ? 4 : 3,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.accent,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.graphic_eq_rounded,
                                    size: 11,
                                    color: Colors.white,
                                  ),
                                  if (isBig) ...[
                                    const SizedBox(width: 4),
                                    const Text(
                                      'PLAYING',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 9,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),

                    // Play Icon Glow in Center for Big Tile
                    if (isBig && !isOpening)
                      Center(
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black.withValues(alpha: 0.5),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: const Icon(
                            Icons.play_arrow_rounded,
                            size: 28,
                            color: Colors.white,
                          ),
                        ),
                      ),

                    // Play Center Indicator on Opening
                    if (isOpening)
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.75),
                            shape: BoxShape.circle,
                          ),
                          child: const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              color: AppColors.accent,
                              strokeWidth: 2.5,
                            ),
                          ),
                        ),
                      ),

                    // Bottom Details
                    Positioned(
                      left: isBig ? 14 : 10,
                      right: isBig ? 14 : 10,
                      bottom: isBig ? 14 : 10,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            song.title,
                            maxLines: isBig ? 2 : 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isPlayingThis
                                  ? AppColors.accent
                                  : Colors.white,
                              fontSize: isBig ? 15 : 12,
                              fontWeight: isBig
                                  ? FontWeight.w800
                                  : FontWeight.w700,
                              shadows: const [
                                Shadow(color: Colors.black, blurRadius: 4),
                              ],
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            song.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.8),
                              fontSize: isBig ? 12 : 10.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (_layoutMode == CategoryLayoutMode.waterfall) {
      return AspectRatio(aspectRatio: isTall ? 0.62 : 0.82, child: cardContent);
    }
    return cardContent;
  }

  Widget _skeletonGrid() {
    final width = MediaQuery.sizeOf(context).width;
    final hPad = _horizontalPadding(width);

    if (_layoutMode == CategoryLayoutMode.mosaic) {
      final cols = _mosaicColumns(width);
      final pattern = _mosaicPattern(cols);
      return SliverPadding(
        padding: EdgeInsets.symmetric(horizontal: hPad),
        sliver: SliverGrid(
          gridDelegate: SliverQuiltedGridDelegate(
            crossAxisCount: cols,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            pattern: pattern,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, index) => Container(
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
                    color: AppColors.accent,
                    strokeWidth: 2,
                  ),
                ),
              ),
            ),
            childCount: pattern.length,
          ),
        ),
      );
    }

    final cols = _gridColumns(width);
    return SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: hPad),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          mainAxisSpacing: 14,
          crossAxisSpacing: 14,
          childAspectRatio: 0.74,
        ),
        delegate: SliverChildBuilderDelegate((context, index) {
          return Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white10),
            ),
            child: const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: AppColors.accent,
                  strokeWidth: 2,
                ),
              ),
            ),
          );
        }, childCount: cols * 2),
      ),
    );
  }

  Widget _errorWidget() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 48,
              color: Colors.redAccent,
            ),
            const SizedBox(height: 12),
            Text(
              _error ?? 'An error occurred',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
              onPressed: _loadInitial,
              child: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyWidget() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.music_off_rounded,
              size: 48,
              color: AppColors.muted,
            ),
            const SizedBox(height: 12),
            const Text(
              'No songs found in this category.',
              style: TextStyle(color: AppColors.muted, fontSize: 14),
            ),
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.surfaceElevated,
              ),
              onPressed: () {
                _searchController.clear();
                _loadInitial();
              },
              child: const Text('Reset filter'),
            ),
          ],
        ),
      ),
    );
  }

  Widget? _nowPlayingBar() {
    return StreamBuilder<List<Song>>(
      stream: _audio.queueStream,
      initialData: _audio.queue,
      builder: (context, queueSnap) {
        return StreamBuilder<int?>(
          stream: _audio.currentIndexStream,
          initialData: _audio.currentIndex,
          builder: (context, idxSnap) {
            final queue = queueSnap.data ?? const <Song>[];
            final currentIndex = idxSnap.data;
            if (currentIndex == null ||
                currentIndex < 0 ||
                currentIndex >= queue.length) {
              return const SizedBox.shrink();
            }
            final currentSong = queue[currentIndex];

            return Container(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white12),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black54,
                    blurRadius: 16,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: InkWell(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const MusicPlayerPage()),
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(
                        currentSong.imageUrl,
                        width: 44,
                        height: 44,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 44,
                          height: 44,
                          color: AppColors.surface,
                          child: const Icon(Icons.music_note_rounded, size: 20),
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
                            currentSong.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            currentSong.artist,
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
                    IconButton(
                      icon: const Icon(
                        Icons.open_in_full_rounded,
                        size: 20,
                        color: AppColors.accent,
                      ),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const MusicPlayerPage(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
