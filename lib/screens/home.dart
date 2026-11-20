import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../models/song.dart';
import '../services/audio_service.dart';
import '../services/home_widget_service.dart';
import '../services/monochrome_api.dart';
import '../services/playlist_service.dart';
import '../theme/app_theme.dart';
import 'music_player_page.dart';
import 'listening_history_page.dart';
import 'discover_page.dart';
import 'category_grid_page.dart';
import 'library_page.dart';
import 'settings_page.dart';
import '../widgets/listening_streak_heatmap.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _audio = GlobalAudioService();
  final _playlistService = PlaylistService();
  Map<String, dynamic> _stats = const {};
  bool _statsLoading = false;
  DateTime? _statsLoadedAt;

  bool _isSearchOpen = false;
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  Timer? _searchDebounce;
  List<Song> _suggestions = const [];
  bool _suggestionsLoading = false;
  int _searchRequestId = 0;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _openSearch() {
    setState(() {
      _isSearchOpen = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocusNode.requestFocus();
    });
  }

  void _closeSearch() {
    _searchDebounce?.cancel();
    _searchFocusNode.unfocus();
    setState(() {
      _isSearchOpen = false;
      _suggestionsLoading = false;
      _suggestions = const [];
      _searchController.clear();
    });
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    final query = value.trim();
    if (query.isEmpty) {
      setState(() {
        _suggestions = const [];
        _suggestionsLoading = false;
      });
      return;
    }
    setState(() {
      _suggestionsLoading = true;
    });
    final requestId = ++_searchRequestId;
    _searchDebounce = Timer(const Duration(milliseconds: 280), () async {
      try {
        final songs = await MonochromeApi().searchPage(query, limit: 6);
        if (!mounted || requestId != _searchRequestId) return;
        setState(() {
          _suggestions = songs;
          _suggestionsLoading = false;
        });
      } catch (_) {
        if (!mounted || requestId != _searchRequestId) return;
        setState(() {
          _suggestions = const [];
          _suggestionsLoading = false;
        });
      }
    });
  }

  void _submitSearch(String query) {
    final clean = query.trim();
    _closeSearch();
    if (clean.isNotEmpty) {
      _openDiscover(clean);
    }
  }

  Future<void> _loadStats({bool force = false}) async {
    if (_statsLoading) return;
    final lastLoaded = _statsLoadedAt;
    if (!force && lastLoaded != null &&
        DateTime.now().difference(lastLoaded) < const Duration(minutes: 5)) {
      return;
    }
    _statsLoading = true;
    try {
      final data = await _playlistService.stats();
      _statsLoadedAt = DateTime.now();
      if (mounted) {
        setState(() => _stats = data);
      }
      final hours = (data['total_played_hours'] as num?)?.toInt() ?? 0;
      final mins = (data['daily_minutes'] as num?)?.toInt() ?? 0;
      final streak = (data['listening_streak_days'] as num?)?.toInt() ?? 0;
      final topSongs = (data['top_songs'] as List? ?? const [])
          .whereType<Map>()
          .toList();
      final topTrack = topSongs.isNotEmpty
          ? '${topSongs.first['title'] ?? ''} · ${topSongs.first['artist'] ?? ''}'
          : 'Keep listening on Loopin';
      final topPlays = topSongs.isNotEmpty
          ? (topSongs.first['plays']?.toString() ?? '★')
          : '★';
      if (!mounted) return;
      await HomeWidgetService.updateStats(
        totalPlayedHours: hours,
        dailyMinutes: mins,
        listeningStreakDays: streak,
        topTrack: topTrack,
        topPlays: topPlays,
      );
    } catch (_) {
      // Keep the last rendered snapshot; retry only on an explicit refresh.
    } finally {
      _statsLoading = false;
    }
  }

  static const _languages = [
    ('Malayalam', 'Malayalam music'),
    ('Hindi', 'Hindi music'),
    ('Tamil', 'Tamil music'),
    ('Telugu', 'Telugu music'),
    ('English', 'English music'),
  ];

  static const _moods = [
    ('Chill', 'Late-night & laid-back', 'chill music'),
    ('Romantic', 'For the feelings', 'romantic songs'),
    ('Workout', 'Energy on repeat', 'workout music'),
    ('Lofi', 'Slow down', 'lofi music'),
    ('Trending', 'What is playing now', 'trending music'),
  ];

  static const _artists = [
    ('A. R. Rahman', 'A. R. Rahman'),
    ('Anirudh', 'Anirudh Ravichander'),
    ('Sushin Shyam', 'Sushin Shyam'),
    ('Vineeth Sreenivasan', 'Vineeth Sreenivasan'),
    ('Shaan Rahman', 'Shaan Rahman'),
  ];

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = width >= 900;
    final hPad = isDesktop ? 32.0 : 20.0;
    final showSuggestions = _isSearchOpen &&
        (_searchController.text.trim().isNotEmpty ||
            _suggestionsLoading ||
            _suggestions.isNotEmpty);

    return PopScope(
      canPop: !_isSearchOpen,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_isSearchOpen) {
          _closeSearch();
        }
      },
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: Stack(
            children: [
              NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  if (notification is ScrollStartNotification && _isSearchOpen) {
                    _searchFocusNode.unfocus();
                  }
                  return false;
                },
                child: GestureDetector(
                  behavior: _isSearchOpen
                      ? HitTestBehavior.opaque
                      : HitTestBehavior.deferToChild,
                  onTap: _isSearchOpen ? _closeSearch : null,
                  child: RefreshIndicator(
                    onRefresh: () => _loadStats(force: true),
                    child: CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        SliverToBoxAdapter(child: _header(context)),
                        const SliverToBoxAdapter(child: SizedBox(height: 8)),
                        SliverToBoxAdapter(
                          child: _sectionTitle(
                            'Made for you',
                            'See all',
                            () => _openCategory(
                              'Made for you',
                              'Malayalam hits',
                              subtitle: 'Personalized Mix',
                            ),
                          ),
                        ),
                        SliverToBoxAdapter(child: _featured()),
                        SliverToBoxAdapter(child: _topSongs()),
                        SliverToBoxAdapter(
                          child: _sectionTitle(
                            'Browse by language',
                            'See all',
                            () => _openCategory(
                              'Browse by language',
                              'Indian music hits',
                              subtitle: 'Regional Hits',
                            ),
                          ),
                        ),
                        SliverToBoxAdapter(child: _languageRow()),
                        SliverToBoxAdapter(
                          child: _sectionTitle(
                            'Play by mood',
                            'See all',
                            () => _openCategory(
                              'Play by mood',
                              'trending mood music',
                              subtitle: 'Curated Moods',
                            ),
                          ),
                        ),
                        SliverToBoxAdapter(child: _moodRow()),
                        SliverToBoxAdapter(
                          child: _sectionTitle(
                            'Popular artists',
                            'See all',
                            () => _openCategory(
                              'Popular artists',
                              'top artists songs',
                              subtitle: 'Trending Artists',
                            ),
                          ),
                        ),
                        SliverToBoxAdapter(child: _artistsRow()),
                        SliverToBoxAdapter(
                          child: _sectionTitle(
                            'Recently played',
                            'View all',
                            () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const ListeningHistoryPage(),
                              ),
                            ),
                          ),
                        ),
                        const SliverToBoxAdapter(child: RecentListeningSection()),
                        const SliverToBoxAdapter(child: SizedBox(height: 20)),
                        SliverToBoxAdapter(child: _usageStats()),
                        const SliverToBoxAdapter(child: SizedBox(height: 20)),
                        SliverToBoxAdapter(child: _listeningStreakHeatmapSection()),
                        const SliverToBoxAdapter(child: SizedBox(height: 120)),
                      ],
                    ),
                  ),
                ),
              ),
              if (showSuggestions)
                Positioned(
                  top: isDesktop ? 76 : 72,
                  left: hPad,
                  right: hPad,
                  child: _buildSuggestionsOverlay(context, isDesktop),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = width >= 900;
    final hPad = isDesktop ? 32.0 : 20.0;

    return Padding(
      padding: EdgeInsets.fromLTRB(hPad, 18, hPad, 12),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          return FadeTransition(
            opacity: animation,
            child: SizeTransition(
              sizeFactor: animation,
              axis: Axis.horizontal,
              child: child,
            ),
          );
        },
        child: _isSearchOpen
            ? _buildSearchHeader(context, isDesktop)
            : _buildStandardHeader(context, isDesktop),
      ),
    );
  }

  Widget _buildStandardHeader(BuildContext context, bool isDesktop) {
    return Row(
      key: const ValueKey('standard_header'),
      children: [
        Image.asset('assets/images/Lloopin.png', height: isDesktop ? 38 : 34),
        if (isDesktop) ...[
          const SizedBox(width: 14),
          const Text(
            'Good music, endlessly looped.',
            style: TextStyle(
              color: AppColors.muted,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
        const Spacer(),
        IconButton(
          tooltip: 'Search',
          onPressed: _openSearch,
          icon: const Icon(Icons.search_rounded),
        ),
        IconButton(
          tooltip: 'Settings',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SettingsPage()),
          ),
          icon: const Icon(Icons.settings_outlined),
        ),
      ],
    );
  }

  Widget _buildSearchHeader(BuildContext context, bool isDesktop) {
    return Row(
      key: const ValueKey('search_header'),
      children: [
        Expanded(
          child: Container(
            height: 46,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(23),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.14),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Close search',
                  splashRadius: 20,
                  icon: const Icon(
                    Icons.arrow_back_rounded,
                    size: 20,
                    color: Colors.white70,
                  ),
                  onPressed: _closeSearch,
                ),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    cursorColor: AppColors.accent,
                    textInputAction: TextInputAction.search,
                    decoration: const InputDecoration(
                      hintText: 'Search songs, albums, artists...',
                      hintStyle: TextStyle(
                        color: AppColors.muted,
                        fontSize: 13.5,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 10),
                    ),
                    onChanged: _onSearchChanged,
                    onSubmitted: _submitSearch,
                  ),
                ),
                if (_suggestionsLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.accent,
                      ),
                    ),
                  )
                else if (_searchController.text.isNotEmpty)
                  IconButton(
                    tooltip: 'Clear',
                    splashRadius: 18,
                    icon: const Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: AppColors.muted,
                    ),
                    onPressed: () {
                      _searchController.clear();
                      _onSearchChanged('');
                    },
                  ),
                IconButton(
                  tooltip: 'Search everywhere',
                  splashRadius: 20,
                  icon: const Icon(
                    Icons.search_rounded,
                    size: 20,
                    color: AppColors.accent,
                  ),
                  onPressed: () => _submitSearch(_searchController.text),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSuggestionsOverlay(BuildContext context, bool isDesktop) {
    final query = _searchController.text.trim();
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xF218181B),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.12),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.48,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_suggestionsLoading && _suggestions.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.accent,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          query.isNotEmpty
                              ? 'Searching for "$query"...'
                              : 'Searching...',
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  )
                else if (_suggestions.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'No instant matches for "$query"',
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: () => _submitSearch(query),
                          icon: const Icon(Icons.travel_explore_rounded, size: 18),
                          label: const Text('Search everywhere on Loopin'),
                        ),
                      ],
                    ),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      itemCount: _suggestions.length,
                      separatorBuilder: (_, __) => Divider(
                        height: 1,
                        thickness: 0.5,
                        color: Colors.white.withValues(alpha: 0.06),
                      ),
                      itemBuilder: (context, index) {
                        final song = _suggestions[index];
                        return ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 2,
                          ),
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: song.imageUrl.isNotEmpty
                                ? Image.network(
                                    song.imageUrl,
                                    width: 42,
                                    height: 42,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => _coverPlaceholder(),
                                  )
                                : _coverPlaceholder(),
                          ),
                          title: Text(
                            song.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            song.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 11.5,
                            ),
                          ),
                          trailing: Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.accent.withValues(alpha: 0.15),
                            ),
                            child: const Icon(
                              Icons.play_arrow_rounded,
                              size: 18,
                              color: AppColors.accent,
                            ),
                          ),
                          onTap: () {
                            _closeSearch();
                            unawaited(GlobalAudioService().playSong(song));
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => MusicPlayerPage(initialSong: song),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                if (query.isNotEmpty)
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.25),
                      border: Border(
                        top: BorderSide(
                          color: Colors.white.withValues(alpha: 0.08),
                          width: 1,
                        ),
                      ),
                    ),
                    child: InkWell(
                      onTap: () => _submitSearch(query),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.search_rounded,
                              size: 18,
                              color: AppColors.accent,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'See all results for "$query"',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const Icon(
                              Icons.arrow_forward_rounded,
                              size: 16,
                              color: AppColors.muted,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _coverPlaceholder() {
    return Container(
      width: 42,
      height: 42,
      color: AppColors.surfaceElevated,
      alignment: Alignment.center,
      child: const Icon(
        Icons.music_note_rounded,
        color: AppColors.muted,
        size: 20,
      ),
    );
  }

  Widget _topSongs() {
    final topSongs = (_stats['top_songs'] as List? ?? const [])
        .whereType<Map>()
        .toList();
    if (topSongs.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Top on repeat', 'See all', () => _openLibrary()),
        SizedBox(
          height: 218,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            scrollDirection: Axis.horizontal,
            itemCount: topSongs.take(10).length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final item = topSongs[index];
              final title = item['title']?.toString() ?? 'Unknown track';
              final artist = item['artist']?.toString() ?? 'Unknown artist';
              final id = item['song_id']?.toString() ??
                  item['id']?.toString() ??
                  '';
              final imageUrl = item['image_url']?.toString() ??
                  item['imageUrl']?.toString() ??
                  '';
              final plays = (item['plays'] as num?)?.toInt() ?? 0;
              final rawMedia = item['media_url']?.toString() ?? '';
              final song = Song(
                id: id.isNotEmpty ? id : 'top_${title.hashCode}',
                title: title,
                artist: artist,
                imageUrl: imageUrl,
                mediaUrl: rawMedia.contains('/catalog/music/stream/') ? '' : rawMedia,
              );

              return SizedBox(
                width: 148,
                child: Material(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(18),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => _play(song, const []),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Stack(
                          children: [
                            SizedBox(
                              width: 148,
                              height: 140,
                              child: imageUrl.isNotEmpty
                                  ? Image.network(
                                      imageUrl,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => _topSongPlaceholder(),
                                    )
                                  : _topSongPlaceholder(),
                            ),
                            Positioned(
                              right: 8,
                              bottom: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.72),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '$plays plays',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(10, 9, 10, 2),
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.text,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Text(
                            artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 10,
                              color: AppColors.muted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _topSongPlaceholder() => Container(
        color: AppColors.surfaceElevated,
        alignment: Alignment.center,
        child: const Icon(Icons.music_note_rounded, size: 34, color: AppColors.muted),
      );

  Widget _buildTrackProgressBar(Song song) {
    return StreamBuilder<int?>(
      stream: _audio.currentIndexStream,
      initialData: _audio.currentIndex,
      builder: (context, indexSnap) {
        final curIdx = indexSnap.data;
        final queue = _audio.queue;
        final isPlayingSong = curIdx != null &&
            curIdx >= 0 &&
            curIdx < queue.length &&
            (queue[curIdx].id == song.id ||
                (queue[curIdx].title.toLowerCase() == song.title.toLowerCase() &&
                    queue[curIdx].artist.toLowerCase() == song.artist.toLowerCase()));

        if (!isPlayingSong) return const SizedBox.shrink();

        return FutureBuilder<AudioPlayer>(
          future: _audio.player,
          builder: (context, playerSnap) {
            final player = playerSnap.data;
            if (player == null) return const SizedBox.shrink();

            return StreamBuilder<Duration>(
              stream: _audio.positionStream,
              initialData: Duration.zero,
              builder: (context, posSnap) {
                return StreamBuilder<Duration?>(
                  stream: player.durationStream,
                  initialData: player.duration,
                  builder: (context, durSnap) {
                    final pos = posSnap.data ?? Duration.zero;
                    final dur = durSnap.data ?? Duration.zero;
                    final progress = dur.inMilliseconds > 0
                        ? (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0)
                        : 0.0;

                    return Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 2.5,
                          backgroundColor: Colors.white12,
                          valueColor: const AlwaysStoppedAnimation<Color>(AppColors.accent),
                        ),
                      ),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _usageStats() {
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = width >= 960;
    final hPad = isDesktop ? 32.0 : 20.0;
    final hours = _stats['total_played_hours'] ?? 0;
    final daily = _stats['daily_minutes'] ?? 0;
    final streak = _stats['listening_streak_days'] ?? 0;
    final topSongs = (_stats['top_songs'] as List? ?? const [])
        .whereType<Map>()
        .toList();

    final metricCards = [
      Expanded(
        child: _statCard(
          icon: Icons.headphones_rounded,
          label: 'Total Played',
          value: '$hours h',
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: _statCard(
          icon: Icons.graphic_eq_rounded,
          label: 'Today',
          value: '$daily min',
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: _statCard(
          icon: Icons.bolt_rounded,
          label: 'Streak',
          value: '$streak d',
        ),
      ),
    ];

    final topTrackWidgets = topSongs.take(2).toList().asMap().entries.map((entry) {
      final rank = entry.key + 1;
      final item = entry.value;
      final title = item['title']?.toString() ?? 'Unknown';
      final artist = item['artist']?.toString() ?? '';
      final plays = item['plays']?.toString() ?? '0';
      final id = item['song_id']?.toString() ?? item['id']?.toString() ?? '';
      final imageUrl = item['image_url']?.toString() ?? item['imageUrl']?.toString() ?? '';
      final rawMedia = item['media_url']?.toString() ?? '';
      final song = Song(
        id: id.isNotEmpty ? id : 'top_${title.hashCode}',
        title: title,
        artist: artist,
        imageUrl: imageUrl,
        mediaUrl: rawMedia.contains('/catalog/music/stream/') ? '' : rawMedia,
      );

      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.divider),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _play(song, const []),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: rank == 1
                          ? AppColors.accent.withValues(alpha: 0.15)
                          : AppColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: rank == 1
                            ? AppColors.accent.withValues(alpha: 0.35)
                            : AppColors.divider,
                      ),
                    ),
                    child: Text(
                      '#$rank',
                      style: TextStyle(
                        color: rank == 1 ? AppColors.accent : AppColors.muted,
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: AppColors.text,
                          ),
                        ),
                        if (artist.isNotEmpty)
                          Text(
                            artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 11,
                            ),
                          ),
                        _buildTrackProgressBar(song),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.play_arrow_rounded,
                          size: 14,
                          color: AppColors.accent,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          '$plays plays',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }).toList();

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: hPad),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.divider),
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Row with Title Badge & Streak Badge
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: AppColors.accent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.insights_rounded,
                          size: 16,
                          color: AppColors.accent,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'LISTENING ACTIVITY',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.2,
                              color: AppColors.accent,
                            ),
                          ),
                          Text(
                            'Your music pulse',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (streak > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.divider),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.local_fire_department_rounded,
                            size: 15,
                            color: AppColors.accent,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$streak d streak',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: AppColors.text,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              if (isDesktop)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 5,
                      child: Row(children: metricCards),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      flex: 6,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                topSongs.isNotEmpty ? Icons.repeat_rounded : Icons.auto_awesome_rounded,
                                size: 15,
                                color: AppColors.muted,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                topSongs.isNotEmpty ? 'Top on Repeat' : 'Your Listening Overview',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.3,
                                  color: AppColors.text,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          if (topSongs.isNotEmpty)
                            ...topTrackWidgets
                          else
                            _desktopListeningHighlights(),
                        ],
                      ),
                    ),
                  ],
                )
              else ...[
                Row(children: metricCards),
                if (topSongs.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  const Row(
                    children: [
                      Icon(Icons.repeat_rounded, size: 15, color: AppColors.muted),
                      SizedBox(width: 6),
                      Text(
                        'Top on Repeat',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                          color: AppColors.text,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ...topTrackWidgets,
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _desktopListeningHighlights() {
    final totalPlays = (_stats['total_plays'] as num?)?.toInt() ?? 0;
    final totalLikes = (_stats['total_likes'] as num?)?.toInt() ?? 0;
    final dailyMinutes = (_stats['daily_minutes'] as num?)?.toInt() ?? 0;
    final totalHours = (_stats['total_played_hours'] as num?)?.toInt() ?? 0;

    Widget highlight(IconData icon, String label, String value) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 17, color: AppColors.accent),
              const SizedBox(height: 10),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: const TextStyle(fontSize: 11, color: AppColors.muted),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Your listening habits at a glance.',
          style: TextStyle(fontSize: 12, color: AppColors.muted),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            highlight(Icons.play_circle_outline_rounded, 'Total plays', '$totalPlays'),
            const SizedBox(width: 10),
            highlight(Icons.favorite_border_rounded, 'Liked songs', '$totalLikes'),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            highlight(Icons.headphones_rounded, 'Listening time', '${totalHours}h'),
            const SizedBox(width: 10),
            highlight(Icons.bolt_rounded, 'Today', '${dailyMinutes}m'),
          ],
        ),
      ],
    );
  }

  Widget _listeningStreakHeatmapSection() {
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = width >= 960;
    final hPad = isDesktop ? 32.0 : 20.0;
    final dailyPlays = Map<String, dynamic>.from(
      _stats['daily_plays'] as Map? ?? const {},
    );
    final streak = (_stats['listening_streak_days'] as num?)?.toInt() ?? 0;
    final totalPlays = (_stats['total_plays'] as num?)?.toInt() ?? 0;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: hPad),
      child: ListeningStreakHeatmap(
        dailyPlays: dailyPlays,
        streakDays: streak,
        totalPlays: totalPlays,
      ),
    );
  }

  Widget _statCard({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: AppColors.accent, size: 16),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppColors.text,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title, String action, VoidCallback onAction) {
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = width >= 900;
    return Padding(
      padding: EdgeInsets.fromLTRB(isDesktop ? 32 : 20, 8, isDesktop ? 32 : 20, 12),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(fontSize: isDesktop ? 23 : 21, fontWeight: FontWeight.w700),
          ),
          const Spacer(),
          TextButton(
            onPressed: onAction,
            child: Text(action, style: const TextStyle(color: AppColors.muted)),
          ),
        ],
      ),
    );
  }

  Widget _featured() {
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = width >= 900;
    final hPad = isDesktop ? 32.0 : 20.0;
    const cards = [
      ('Malayalam Essentials', 'A place to start', 'Malayalam hits'),
      ('Night Drive', 'Neon lights. Good music.', 'night drive music'),
      ('Loopin Mix', 'Your music, your loop.', 'lofi music'),
    ];

    if (isDesktop) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: hPad),
        child: SizedBox(
          height: 200,
          child: Row(
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                if (i > 0) const SizedBox(width: 14),
                Expanded(child: _featuredCard(cards[i].$1, cards[i].$2, cards[i].$3, fillWidth: true)),
              ],
            ],
          ),
        ),
      );
    }

    return SizedBox(
      height: 190,
      child: ListView.separated(
        padding: EdgeInsets.symmetric(horizontal: hPad),
        scrollDirection: Axis.horizontal,
        itemCount: cards.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, index) {
          final card = cards[index];
          return _featuredCard(card.$1, card.$2, card.$3);
        },
      ),
    );
  }

  Widget _featuredCard(String title, String subtitle, String query, {bool fillWidth = false}) {
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: () => _openCategory(title, query, subtitle: subtitle),
      child: Container(
        width: fillWidth ? null : 285,
        margin: const EdgeInsets.only(right: 0),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white10),
          color: AppColors.surfaceElevated,
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _categoryImage(query),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.08),
                    Colors.black.withValues(alpha: 0.82),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'LOOPIN',
                    style: TextStyle(
                      color: AppColors.accent,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(subtitle, style: const TextStyle(color: Colors.white70)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _languageRow() {
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = width >= 900;
    final hPad = isDesktop ? 32.0 : 20.0;

    Widget card(String name, String query, {double? fixedWidth}) {
      return InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _openCategory(
          name,
          query,
          subtitle: '$name Music & Hits',
        ),
        child: Container(
          width: fixedWidth,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white10),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _categoryImage(query),
              _imageOverlay(),
              Align(
                alignment: Alignment.bottomLeft,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (isDesktop) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: hPad),
        child: SizedBox(
          height: 120,
          child: Row(
            children: [
              for (var i = 0; i < _languages.length; i++) ...[
                if (i > 0) const SizedBox(width: 12),
                Expanded(child: card(_languages[i].$1, _languages[i].$2)),
              ],
            ],
          ),
        ),
      );
    }

    return SizedBox(
      height: 112,
      child: ListView.separated(
        padding: EdgeInsets.symmetric(horizontal: hPad),
        scrollDirection: Axis.horizontal,
        itemCount: _languages.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, index) => card(_languages[index].$1, _languages[index].$2, fixedWidth: 104),
      ),
    );
  }

  void _openCategory(
    String title,
    String query, {
    String? subtitle,
    String? bannerImageUrl,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CategoryGridPage(
          title: title,
          query: query,
          subtitle: subtitle,
          bannerImageUrl: bannerImageUrl ?? _CategoryThumbnail.thumbnailFor(query),
        ),
      ),
    );
  }

  void _openDiscover(String query) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DiscoverPage(initialQuery: query)),
    );
  }

  void _openLibrary() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const LibraryPage()),
    );
  }

  Widget _moodRow() {
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = width >= 900;
    final hPad = isDesktop ? 32.0 : 20.0;

    Widget card(String title, String subtitle, String query, {double? fixedWidth}) {
      return InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _openCategory(title, query, subtitle: subtitle),
        child: Container(
          width: fixedWidth,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white10),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _categoryImage(query),
              _imageOverlay(),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (isDesktop) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: hPad),
        child: SizedBox(
          height: 145,
          child: Row(
            children: [
              for (var i = 0; i < _moods.length; i++) ...[
                if (i > 0) const SizedBox(width: 12),
                Expanded(child: card(_moods[i].$1, _moods[i].$2, _moods[i].$3)),
              ],
            ],
          ),
        ),
      );
    }

    return SizedBox(
      height: 138,
      child: ListView.separated(
        padding: EdgeInsets.symmetric(horizontal: hPad),
        scrollDirection: Axis.horizontal,
        itemCount: _moods.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, index) => card(_moods[index].$1, _moods[index].$2, _moods[index].$3, fixedWidth: 160),
      ),
    );
  }

  Widget _artistsRow() {
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = width >= 900;
    final hPad = isDesktop ? 32.0 : 20.0;

    Widget card(String name, String query) {
      return InkWell(
        borderRadius: BorderRadius.circular(44),
        onTap: () => _openCategory(
          name,
          query,
          subtitle: 'Top Tracks by $name',
        ),
        child: SizedBox(
          width: isDesktop ? null : 86,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipOval(
                child: SizedBox(
                  width: isDesktop ? 86 : 72,
                  height: isDesktop ? 86 : 72,
                  child: _categoryImage(query),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                name,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: isDesktop ? 12 : 11, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      );
    }

    if (isDesktop) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: hPad),
        child: SizedBox(
          height: 145,
          child: Row(
            children: [
              for (var i = 0; i < _artists.length; i++) ...[
                if (i > 0) const SizedBox(width: 16),
                Expanded(child: card(_artists[i].$1, _artists[i].$2)),
              ],
            ],
          ),
        ),
      );
    }

    return SizedBox(
      height: 138,
      child: ListView.separated(
        padding: EdgeInsets.symmetric(horizontal: hPad),
        scrollDirection: Axis.horizontal,
        itemCount: _artists.length,
        separatorBuilder: (_, __) => const SizedBox(width: 18),
        itemBuilder: (_, index) => card(_artists[index].$1, _artists[index].$2),
      ),
    );
  }

  Widget _categoryImage(String query) {
    return _CategoryThumbnail(query: query);
  }

  Widget _imageOverlay() {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.02),
            Colors.black.withValues(alpha: 0.78),
          ],
        ),
      ),
    );
  }

  Future<void> _play(Song song, List<Song> contextSongs) async {
    try {
      await _audio.playSong(song, context: contextSongs);
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => MusicPlayerPage(initialSong: song)),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not play "${song.title}": $error')),
      );
    }
  }
}

class _CategoryThumbnail extends StatefulWidget {
  final String query;
  const _CategoryThumbnail({required this.query});

  static final Map<String, String> _cache = {
    // Featured / Made for you
    'Malayalam hits': 'https://c.saavncdn.com/475/KALYANI-Remix-Malayalam-2026-20260622131127-500x500.jpg',
    'night drive music': 'https://c.saavncdn.com/236/Night-Drive-Chill-Hindi-2026-20260911200550-500x500.jpg',
    'lofi music': 'https://c.saavncdn.com/570/Kishor-Avastha-Lofi-Haryanvi-2026-20260930203926-500x500.jpg',

    // Languages
    'Malayalam music': 'https://c.saavncdn.com/475/KALYANI-Remix-Malayalam-2026-20260622131127-500x500.jpg',
    'Hindi music': 'https://c.saavncdn.com/320/Tu-Mil-Jaaye-From-KING-Hindi-2026-20261031131042-500x500.jpg',
    'Tamil music': 'https://c.saavncdn.com/696/Veezha-Veera-From-OM-Chapter-1-Udhiram-The-Blood-Wood-Tamil-Tamil-2026-20261019161818-500x500.jpg',
    'Telugu music': 'https://c.saavncdn.com/993/Veera-Veera-From-OM-Chapter-1-Udhiram-The-Blood-Wood-Telugu-Telugu-2026-20261019161819-500x500.jpg',
    'English music': 'https://c.saavncdn.com/950/8-Parche-English-2020-20260401031217-500x500.jpg',

    // Moods
    'chill music': 'https://c.saavncdn.com/114/Chill-Unknown-2026-20260529123318-500x500.jpg',
    'romantic songs': 'https://c.saavncdn.com/424/Romantic-Mashup-Hindi-2018-20230608012356-500x500.jpg',
    'workout music': 'https://c.saavncdn.com/014/Workout-Punjabi-2015-500x500.jpg',
    'trending music': 'https://c.saavncdn.com/400/Trending-Punjabi-2024-20241114144017-500x500.jpg',

    // Featured artists
    'A. R. Rahman': 'https://c.saavncdn.com/316/Mangal-Rang-From-Ramayana-Hindi-2026-20261024141033-500x500.jpg',
    'Anirudh Ravichander': 'https://c.saavncdn.com/557/Ala-Bolelo-From-Jailer-2-Tamil-2026-20260821084843-500x500.jpg',
    'Sushin Shyam': 'https://c.saavncdn.com/015/Aeroplane-From-Scene-Tamil-2026-20261019143000-500x500.jpg',
    'Vineeth Sreenivasan': 'https://c.saavncdn.com/205/Velipadinte-Pusthakam-Malayalam-2024-20250425150549-500x500.jpg',
    'Shaan Rahman': 'https://c.saavncdn.com/625/Onam-Special-Hits-Malayalam-2026-20260814183123-500x500.jpg',
  };

  static final Set<String> _pending = {};

  static String? thumbnailFor(String query) => _cache[query.trim()];

  @override
  State<_CategoryThumbnail> createState() => _CategoryThumbnailState();
}

class _CategoryThumbnailState extends State<_CategoryThumbnail> {
  @override
  void initState() {
    super.initState();
    _resolveThumbnail();
  }

  @override
  void didUpdateWidget(covariant _CategoryThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query != widget.query) {
      _resolveThumbnail();
    }
  }

  void _resolveThumbnail() {
    final query = widget.query.trim();
    if (query.isEmpty || _CategoryThumbnail._cache.containsKey(query) || _CategoryThumbnail._pending.contains(query)) {
      return;
    }
    _CategoryThumbnail._pending.add(query);
    MonochromeApi().searchPage(query, limit: 1).then((songs) {
      _CategoryThumbnail._pending.remove(query);
      if (mounted && songs.isNotEmpty && songs.first.imageUrl.isNotEmpty) {
        setState(() {
          _CategoryThumbnail._cache[query] = songs.first.imageUrl;
        });
      }
    }).catchError((_) {
      _CategoryThumbnail._pending.remove(query);
    });
  }

  @override
  Widget build(BuildContext context) {
    final url = _CategoryThumbnail._cache[widget.query.trim()];

    if (url != null && url.isNotEmpty) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        alignment: Alignment.center,
        filterQuality: FilterQuality.medium,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return _placeholder();
        },
        errorBuilder: (_, __, ___) => _placeholder(),
      );
    }

    return _placeholder();
  }

  Widget _placeholder() {
    return Container(
      color: AppColors.surfaceElevated,
      alignment: Alignment.center,
      child: Icon(
        Icons.graphic_eq_rounded,
        size: 30,
        color: AppColors.muted.withValues(alpha: 0.45),
      ),
    );
  }
}
