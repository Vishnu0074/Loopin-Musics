import 'package:flutter_bloc/flutter_bloc.dart';
import '../models/playlist.dart';
import '../models/song.dart';
import '../services/playlist_service.dart';

sealed class LibraryEvent { const LibraryEvent(); }
class LibraryRequested extends LibraryEvent { const LibraryRequested(); }
class LibraryRefreshed extends LibraryEvent { const LibraryRefreshed(); }
class LikeToggled extends LibraryEvent { final Song song; const LikeToggled(this.song); }
class PlaylistCreationAcknowledged extends LibraryEvent { const PlaylistCreationAcknowledged(); }
class PlaylistCreated extends LibraryEvent { final String name; final bool isPublic; const PlaylistCreated(this.name,{this.isPublic=false}); }
class PlaylistSongAdded extends LibraryEvent { final int playlistId; final Song song; const PlaylistSongAdded(this.playlistId,this.song); }
class PlaylistSongRemoved extends LibraryEvent { final int playlistId; final String songId; const PlaylistSongRemoved(this.playlistId,this.songId); }
class PlaylistReordered extends LibraryEvent { final int playlistId; final List<String> songIds; const PlaylistReordered(this.playlistId,this.songIds); }

class LibraryState {
  final List<Playlist> playlists;
  final List<Song> likedSongs;
  final bool loading;
  final bool mutating;
  final String? error;
  final Set<String> pendingLikeIds;
  final Playlist? createdPlaylist;
  const LibraryState({this.playlists=const [],this.likedSongs=const [],this.loading=false,this.mutating=false,this.error,this.pendingLikeIds=const {},this.createdPlaylist});
  LibraryState copyWith({List<Playlist>? playlists,List<Song>? likedSongs,bool? loading,bool? mutating,String? error,bool clearError=false,Set<String>? pendingLikeIds,Playlist? createdPlaylist,bool clearCreatedPlaylist=false})=>LibraryState(
    playlists:playlists??this.playlists,likedSongs:likedSongs??this.likedSongs,
    loading:loading??this.loading,mutating:mutating??this.mutating,
    error:clearError?null:(error??this.error),pendingLikeIds:pendingLikeIds??this.pendingLikeIds,createdPlaylist:clearCreatedPlaylist?null:(createdPlaylist??this.createdPlaylist),
  );
}

/// UI-first library state: user actions are reflected synchronously, then persisted
/// in the background. Failed writes roll back only their own optimistic change.
class LibraryBloc extends Bloc<LibraryEvent,LibraryState> {
  final PlaylistService repository;
  int _activeMutations = 0;
  int _temporaryPlaylistId = -1;

  LibraryBloc(this.repository):super(const LibraryState()) {
    on<LibraryRequested>((event,emit)=>_load(emit));
    on<LibraryRefreshed>((event,emit)=>_load(emit));
    on<LikeToggled>(_toggleLike);
    on<PlaylistCreated>(_createPlaylist);
    on<PlaylistCreationAcknowledged>((event,emit)=>emit(state.copyWith(clearCreatedPlaylist:true)));
    on<PlaylistSongAdded>(_addSong);
    on<PlaylistSongRemoved>(_removeSong);
    on<PlaylistReordered>(_reorder);
  }

  void _beginMutation(Emitter<LibraryState> emit) {
    _activeMutations++;
    emit(state.copyWith(mutating:true,clearError:true));
  }

  void _endMutation(Emitter<LibraryState> emit) {
    _activeMutations = (_activeMutations - 1).clamp(0, 1 << 30).toInt();
    emit(state.copyWith(mutating:_activeMutations > 0));
  }

  Future<void> _load(Emitter<LibraryState> emit) async {
    // Keep already-rendered content on screen during refresh/resume.
    final hasContent = state.playlists.isNotEmpty || state.likedSongs.isNotEmpty;
    emit(state.copyWith(loading:!hasContent,clearError:true));
    try {
      final results=await Future.wait([repository.list(),repository.likedSongs()]);
      if (isClosed) return;
      // Don't let a background refresh overwrite optimistic state during a write.
      if (_activeMutations == 0) {
        emit(state.copyWith(playlists:results[0] as List<Playlist>,likedSongs:results[1] as List<Song>,loading:false,clearError:true));
      } else {
        emit(state.copyWith(loading:false));
      }
    } catch(error) {
      if (!isClosed) emit(state.copyWith(loading:false,error:error.toString()));
    }
  }

  Future<void> _toggleLike(LikeToggled event,Emitter<LibraryState> emit) async {
    final song=event.song;
    // Ignore duplicate taps while this song's write is in flight.
    if (state.pendingLikeIds.contains(song.id)) return;
    final previous=state.likedSongs;
    final wasLiked=previous.any((item)=>item.id==song.id);
    final optimistic=wasLiked?previous.where((item)=>item.id!=song.id).toList():[song,...previous];
    emit(state.copyWith(likedSongs:optimistic,pendingLikeIds:{...state.pendingLikeIds,song.id},clearError:true));
    try {
      final actual=await repository.toggleLike(song);
      if(actual==wasLiked) throw StateError('The server returned an unexpected like state.');
    } catch(error) {
      if (!isClosed) {
        final current=state.likedSongs;
        final rolledBack=wasLiked
            ? (current.any((item)=>item.id==song.id)?current:[song,...current])
            : current.where((item)=>item.id!=song.id).toList();
        emit(state.copyWith(likedSongs:rolledBack,error:error.toString()));
      }
    } finally {
      if (!isClosed) emit(state.copyWith(pendingLikeIds:{...state.pendingLikeIds}..remove(song.id)));
    }
  }

  Future<void> _createPlaylist(PlaylistCreated event,Emitter<LibraryState> emit) async {
    final tempId=_temporaryPlaylistId--;
    final optimistic=Playlist(id:tempId,name:event.name,songCount:0,isPublic:event.isPublic);
    emit(state.copyWith(playlists:[optimistic,...state.playlists],clearError:true));
    _beginMutation(emit);
    try {
      final created=await repository.create(event.name,isPublic:event.isPublic);
      if (isClosed) return;
      final updated=state.playlists.map((p)=>p.id==tempId?created:p).toList();
      emit(state.copyWith(playlists:updated,createdPlaylist:created));
    } catch(error) {
      if (!isClosed) {
        emit(state.copyWith(playlists:state.playlists.where((p)=>p.id!=tempId).toList(),clearCreatedPlaylist:true,error:error.toString()));
      }
    } finally {
      if (!isClosed) _endMutation(emit);
    }
  }

  Future<void> _addSong(PlaylistSongAdded event,Emitter<LibraryState> emit) async {
    final before=state.playlists;
    final optimistic=before.map((p)=>p.id==event.playlistId
      ? Playlist(id:p.id,name:p.name,imageUrl:p.imageUrl,owner:p.owner,songCount:p.songCount+1,isPublic:p.isPublic)
      : p).toList();
    emit(state.copyWith(playlists:optimistic));
    _beginMutation(emit);
    var succeeded = false;
    try {
      await repository.addSong(event.playlistId,event.song);
      succeeded = true;
    } catch(error) {
      if (!isClosed) emit(state.copyWith(playlists:before,error:error.toString()));
    } finally {
      if (!isClosed) _endMutation(emit);
    }
    if (succeeded && !isClosed) add(const LibraryRefreshed());
  }

  Future<void> _removeSong(PlaylistSongRemoved event,Emitter<LibraryState> emit) async {
    final before=state.playlists;
    final optimistic=before.map((p)=>p.id==event.playlistId
      ? Playlist(id:p.id,name:p.name,imageUrl:p.imageUrl,owner:p.owner,songCount:(p.songCount-1).clamp(0,1<<30).toInt(),isPublic:p.isPublic)
      : p).toList();
    emit(state.copyWith(playlists:optimistic));
    _beginMutation(emit);
    var succeeded = false;
    try {
      await repository.removeSong(event.playlistId,event.songId);
      succeeded = true;
    } catch(error) {
      if (!isClosed) emit(state.copyWith(playlists:before,error:error.toString()));
    } finally {
      if (!isClosed) _endMutation(emit);
    }
    if (succeeded && !isClosed) add(const LibraryRefreshed());
  }

  Future<void> _reorder(PlaylistReordered event,Emitter<LibraryState> emit) async {
    _beginMutation(emit);
    try {
      await repository.reorder(event.playlistId,event.songIds);
    } catch(error) {
      if (!isClosed) emit(state.copyWith(error:error.toString()));
    } finally {
      if (!isClosed) _endMutation(emit);
    }
  }
}
