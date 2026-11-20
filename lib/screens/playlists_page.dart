import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/library_bloc.dart';
import '../models/playlist.dart';
import '../models/song.dart';
import '../services/playlist_service.dart';
import '../services/monochrome_api.dart';
import '../services/audio_service.dart';
import '../theme/app_theme.dart';
import 'music_player_page.dart';
import '../widgets/loopin_snackbar.dart';

class PlaylistsPage extends StatefulWidget { const PlaylistsPage({super.key}); @override State<PlaylistsPage> createState()=>_PlaylistsPageState(); }
class _PlaylistsPageState extends State<PlaylistsPage> {
 Future<void> _load() async { context.read<LibraryBloc>().add(const LibraryRefreshed()); }
 Future<void> _create() async {
   final ctl = TextEditingController();
   bool isPublic = false;
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 560),
      backgroundColor: AppColors.surface,
     builder: (sheetContext) => StatefulBuilder(
       builder: (context, setSheet) => Padding(
         padding: EdgeInsets.only(
           left: 20,
           right: 20,
           top: 20,
           bottom: MediaQuery.of(context).viewInsets.bottom + 20,
         ),
         child: Column(
           mainAxisSize: MainAxisSize.min,
           crossAxisAlignment: CrossAxisAlignment.start,
           children: [
             const Text('Create playlist', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
             const SizedBox(height: 6),
             const Text('Build a collection and choose who can discover it.'),
             const SizedBox(height: 18),
             TextField(
               controller: ctl,
               autofocus: true,
               maxLength: 120,
               decoration: const InputDecoration(labelText: 'Playlist name', hintText: 'e.g. Late Night Malayalam'),
             ),
             const SizedBox(height: 8),
             const Text('Privacy', style: TextStyle(fontWeight: FontWeight.w700)),
             const SizedBox(height: 8),
             Row(
               children: [
                 Expanded(
                   child: ChoiceChip(
                     label: const Text('Private'),
                     avatar: const Icon(Icons.lock_outline, size: 18),
                     selected: !isPublic,
                     onSelected: (_) => setSheet(() => isPublic = false),
                   ),
                 ),
                 const SizedBox(width: 10),
                 Expanded(
                   child: ChoiceChip(
                     label: const Text('Public'),
                     avatar: const Icon(Icons.public, size: 18),
                     selected: isPublic,
                     onSelected: (_) => setSheet(() => isPublic = true),
                   ),
                 ),
               ],
             ),
             const SizedBox(height: 6),
             Text(
               isPublic ? 'Anyone using Loopin can discover and play this playlist.' : 'Only you can see and edit this playlist.',
               style: const TextStyle(color: AppColors.muted),
             ),
             const SizedBox(height: 18),
             SizedBox(
               width: double.infinity,
               child: FilledButton(
                 onPressed: () => Navigator.pop(sheetContext, {'name': ctl.text.trim(), 'is_public': isPublic}),
                 child: const Text('Create playlist'),
               ),
             ),
           ],
         ),
       ),
     ),
   );
   ctl.dispose();
   if (result == null || result['name'].toString().isEmpty) return;
   if (mounted) {
     context.read<LibraryBloc>().add(PlaylistCreated(
       result['name'].toString(),
       isPublic: result['is_public'] == true,
     ));
   }
 }

  @override
  Widget build(BuildContext context) {
    return BlocListener<LibraryBloc, LibraryState>(
      listenWhen: (previous, current) => (previous.createdPlaylist != current.createdPlaylist && current.createdPlaylist != null) || (previous.error != current.error && current.error != null),
      listener: (context, state) {
        if (state.error != null) {
          LoopinSnackBar.show(context, state.error!);
          return;
        }
        final playlist = state.createdPlaylist!;
        context.read<LibraryBloc>().add(const PlaylistCreationAcknowledged());
        Navigator.push(context, MaterialPageRoute(builder: (_) => PlaylistDetailPage(playlist: playlist))).then((_) => _load());
      },
      child: BlocBuilder<LibraryBloc, LibraryState>(
      builder: (context, libraryState) {
        final own = libraryState.playlists.where((p) => p.owner == null || p.isPublic == false).toList();
        final publicItems = libraryState.playlists.where((p) => p.isPublic && p.owner != null).toList();
        final loading = libraryState.loading && libraryState.playlists.isEmpty;
        return Scaffold(
      appBar: AppBar(
        title: const Text('Playlists'),
        actions: [
          IconButton(onPressed: _create, icon: const Icon(Icons.add_rounded)),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isDesktop = constraints.maxWidth >= 900;
                  final columns = constraints.maxWidth >= 1250 ? 3 : (constraints.maxWidth >= 720 ? 2 : 1);
                  final padding = isDesktop ? 28.0 : 16.0;

                  return ListView(
                    padding: EdgeInsets.all(padding),
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Your playlists',
                              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                            ),
                          ),
                          IconButton(
                            onPressed: _create,
                            icon: const Icon(Icons.add_circle_outline),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (own.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 28),
                          child: Center(child: Text('Create your first playlist')),
                        )
                      else if (columns > 1)
                        _playlistGrid(own, columns, showOwner: false)
                      else
                        ...own.map((p) => _playlistTile(p, showOwner: false)),
                      const SizedBox(height: 28),
                      const Text(
                        'Public playlists',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 10),
                      if (publicItems.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 28),
                          child: Center(child: Text('No public playlists yet')),
                        )
                      else if (columns > 1)
                        _playlistGrid(publicItems, columns, showOwner: true)
                      else
                        ...publicItems.map((p) => _playlistTile(p, showOwner: true)),
                    ],
                  );
                },
              ),
            ),
        );
      },
    ),
    );
  }

  Widget _playlistGrid(List<Playlist> items, int columns, {required bool showOwner}) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisExtent: 80,
        crossAxisSpacing: 14,
        mainAxisSpacing: 10,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) => _playlistGridCard(items[i], showOwner: showOwner),
    );
  }

  Widget _playlistGridCard(Playlist p, {required bool showOwner}) {
    return Card(
      color: AppColors.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => PlaylistDetailPage(playlist: p)),
        ).then((_) => _load()),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: AppColors.surfaceElevated,
                  image: p.imageUrl != null && p.imageUrl!.isNotEmpty
                      ? DecorationImage(
                          image: NetworkImage(p.imageUrl!),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: p.imageUrl == null || p.imageUrl!.isEmpty
                    ? Icon(
                        p.isPublic ? Icons.public : Icons.lock_outline,
                        color: AppColors.muted,
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      p.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      showOwner
                          ? ' songs · '
                          : ' songs · ',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.muted, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }

  Widget _playlistTile(Playlist p, {required bool showOwner}) => Card(
    color: AppColors.surface,
    child: ListTile(
      leading: CircleAvatar(
        backgroundImage: p.imageUrl != null && p.imageUrl!.isNotEmpty ? NetworkImage(p.imageUrl!) : null,
        child: p.imageUrl == null || p.imageUrl!.isEmpty ? Icon(p.isPublic ? Icons.public : Icons.lock_outline) : null,
      ),
      title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(showOwner ? ' songs · ' : ' songs · '),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PlaylistDetailPage(playlist: p))).then((_) { _load(); }),
    ),
  );
}

class PlaylistDetailPage extends StatefulWidget {
  final Playlist playlist;
  const PlaylistDetailPage({super.key, required this.playlist});
  @override
  State<PlaylistDetailPage> createState() => _PlaylistDetailPageState();
}

class _PlaylistDetailPageState extends State<PlaylistDetailPage> {
  final _api = PlaylistService();
  List<PlaylistSong> _songs = [];
  bool _loading = true;
  bool _canEdit = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await _api.detail(widget.playlist.id);
      final rows = (d['songs'] as List? ?? const []).whereType<Map>().map((x) => PlaylistSong.fromJson(Map<String, dynamic>.from(x))).toList();
      if (mounted) setState(() { _songs = rows; _canEdit = d['can_edit'] != false; });
    } catch (e) {
      if (mounted) LoopinSnackBar.show(context, e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _add() async {
    if (!_canEdit) return;
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 680),
      backgroundColor: AppColors.surface,
      builder: (_) => _AddSongsSheet(playlistId: widget.playlist.id, api: _api),
    );
    if (changed == true) _load();
  }

  Future<void> _reorder(int oldIndex, int newIndex) async {
    if (!_canEdit) return;
    if (newIndex > oldIndex) newIndex--;
    final x = _songs.removeAt(oldIndex);
    _songs.insert(newIndex, x);
    setState(() {});
    try {
      context.read<LibraryBloc>().add(PlaylistReordered(widget.playlist.id, _songs.map((x) => x.songId).toList()));
    } catch (_) {
      _load();
    }
  }

  Future<void> _play() async {
    if (_songs.isEmpty) return;
    final audio = GlobalAudioService();
    await audio.playSong(
      _songs.first.toSong(),
      context: _songs.map((song) => song.toSong()).toList(growable: false),
    );
    if (mounted) Navigator.push(context, MaterialPageRoute(builder: (_) => const MusicPlayerPage()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.playlist.name),
        actions: [
          if (_canEdit) IconButton(onPressed: _add, icon: const Icon(Icons.add_rounded)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 860),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(' songs', style: const TextStyle(fontWeight: FontWeight.w700)),
                                if (widget.playlist.isPublic)
                                  const Text('Public playlist', style: TextStyle(fontSize: 12, color: AppColors.muted))
                                else
                                  const Text('Private playlist', style: TextStyle(fontSize: 12, color: AppColors.muted)),
                              ],
                            ),
                          ),
                          FilledButton.icon(onPressed: _play, icon: const Icon(Icons.play_arrow), label: const Text('Play')),
                        ],
                      ),
                    ),
                    Expanded(
                      child: _songs.isEmpty
                          ? Center(
                              child: _canEdit
                                  ? OutlinedButton.icon(onPressed: _add, icon: const Icon(Icons.add), label: const Text('Add songs'))
                                  : const Text('This playlist has no songs yet'),
                            )
                          : ReorderableListView.builder(
                              itemCount: _songs.length,
                              onReorderItem: _reorder,
                              itemBuilder: (c, i) {
                                final s = _songs[i];
                                return Card(
                                  key: ValueKey(s.id),
                                  color: AppColors.surface,
                                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                  child: ListTile(
                                    leading: Icon(_canEdit ? Icons.drag_handle : Icons.music_note),
                                    title: Text(s.title),
                                    subtitle: Text(s.artist),
                                    trailing: _canEdit
                                        ? IconButton(
                                            icon: const Icon(Icons.remove_circle_outline),
                                            onPressed: () async {
                                              context.read<LibraryBloc>().add(PlaylistSongRemoved(widget.playlist.id, s.songId));
                                              setState(() => _songs.removeWhere((item) => item.songId == s.songId));
                                            },
                                          )
                                        : null,
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _AddSongsSheet extends StatefulWidget {
  final int playlistId;
  final PlaylistService api;
  const _AddSongsSheet({required this.playlistId, required this.api});
  @override
  State<_AddSongsSheet> createState() => _AddSongsSheetState();
}

class _AddSongsSheetState extends State<_AddSongsSheet> {
  final _search = TextEditingController();
  final _searchApi = MonochromeApi();
  final Set<String> _addedIds = {};
  Map<String, dynamic> _sources = {};
  List<Song> _results = [];
  bool _loading = true;
  bool _changed = false;
  String _tab = 'Liked';

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final data = await widget.api.sources();
      if (mounted) setState(() => _sources = data);
    } catch (e) {
      if (mounted) LoopinSnackBar.show(context, e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Song _song(Map row) => Song(
    id: row['song_id']?.toString() ?? '',
    title: row['title']?.toString() ?? '',
    artist: row['artist']?.toString() ?? '',
    album: row['album']?.toString(),
    imageUrl: row['image_url']?.toString() ?? '',
    mediaUrl: '',
  );

  Future<void> _searchSongs() async {
    if (_search.text.trim().isEmpty) return;
    setState(() => _loading = true);
    try {
      final songs = await _searchApi.searchPage(_search.text.trim(), page: 1, limit: 30);
      if (mounted) setState(() => _results = songs);
    } catch (e) {
      if (mounted) LoopinSnackBar.show(context, e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _add(Song song) async {
    if (song.id.isEmpty || _addedIds.contains(song.id)) return;
    setState(() => _addedIds.add(song.id));
    try {
      context.read<LibraryBloc>().add(PlaylistSongAdded(widget.playlistId, song));
      _changed = true;
      if (mounted) LoopinSnackBar.show(context, 'Adding to playlist…');
    } catch (e) {
      if (mounted) {
        setState(() => _addedIds.remove(song.id));
        LoopinSnackBar.show(context, e.toString());
      }
    }
  }

  @override
  void dispose() { _search.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final raw = _sources[_tab.toLowerCase()] as List? ?? const [];
    final source = raw.whereType<Map>().map(_song).where((s) => s.id.isNotEmpty).toList();
    final songs = _tab == 'Search' ? _results : source;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * .78,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(children: [
              const Expanded(child: Text('Add songs', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800))),
              // Closing the sheet must never wait for network writes.
              TextButton(
                onPressed: () => Navigator.pop(context, _changed),
                child: const Text('Done'),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _search,
              onSubmitted: (_) => _searchSongs(),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Search songs',
                suffixIcon: IconButton(onPressed: _searchSongs, icon: const Icon(Icons.arrow_forward)),
              ),
            ),
          ),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: ['Liked', 'Recent', 'Search'].map((tab) => Padding(
            padding: const EdgeInsets.all(4),
            child: ChoiceChip(label: Text(tab), selected: _tab == tab, onSelected: (_) => setState(() => _tab = tab)),
          )).toList()),
          Expanded(
            child: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  itemCount: songs.length,
                  itemBuilder: (context, index) {
                    final song = songs[index];
                    final added = _addedIds.contains(song.id);
                    return ListTile(
                      title: Text(song.title),
                      subtitle: Text(song.artist),
                      trailing: IconButton(
                        tooltip: added ? 'Added' : 'Add to playlist',
                        icon: Icon(added ? Icons.check_circle : Icons.add_circle_outline, color: added ? Colors.green : null),
                        onPressed: added ? null : () => _add(song),
                      ),
                    );
                  },
                ),
          ),
        ]),
      ),
    );
  }
}
