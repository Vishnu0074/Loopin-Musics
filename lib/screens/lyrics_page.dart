import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/song.dart';
import '../services/audio_service.dart';
import '../services/home_widget_service.dart';
import '../services/lyrics_service.dart';
import '../theme/app_theme.dart';
import '../widgets/loopin_snackbar.dart';

class LyricsPage extends StatefulWidget {
  final Song song;
  const LyricsPage({super.key, required this.song});

  @override
  State<LyricsPage> createState() => _LyricsPageState();
}

class _LyricsPageState extends State<LyricsPage> {
  final _service = LyricsService();
  final _audio = GlobalAudioService();
  final _scrollController = ScrollController();
  final List<GlobalKey> _lineKeys = [];

  late Song _currentSong;
  LyricsData? _data;
  Object? _error;
  bool _loading = true;
  int? _activeLineIndex;
  bool _autoScroll = true;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<int?>? _indexSub;

  @override
  void initState() {
    super.initState();
    _currentSong = widget.song;

    // Instant load from memory cache if preloaded
    final cached = LyricsService.getCached(_currentSong);
    if (cached != null) {
      _data = cached;
      _loading = false;
      _setupLineKeys(cached);
      _activeLineIndex = _calculateActiveLine(_audio.currentPosition);
    }

    _loadSong(_currentSong);
    _subscribePosition();
    _subscribeIndex();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _indexSub?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _setupLineKeys(LyricsData data) {
    _lineKeys.clear();
    for (var i = 0; i < data.lines.length; i++) {
      _lineKeys.add(GlobalKey());
    }
  }

  void _subscribeIndex() {
    _indexSub = _audio.currentIndexStream.listen((index) {
      if (!mounted) return;
      final queue = _audio.queue;
      if (index != null && index >= 0 && index < queue.length) {
        final newSong = queue[index];
        if (newSong.id != _currentSong.id) {
          setState(() {
            _currentSong = newSong;
          });
          _loadSong(newSong);
        }
      }
    });
  }

  void _subscribePosition() {
    _positionSub = _audio.positionStream.listen((position) {
      if (_data == null || !_data!.isSynced || !mounted) return;
      final newIndex = _calculateActiveLine(position);
      if (newIndex != _activeLineIndex) {
        setState(() {
          _activeLineIndex = newIndex;
        });
        if (_autoScroll && newIndex != null) {
          _scrollToActiveLine(newIndex);
        }
      }
    });
  }

  int? _calculateActiveLine(Duration pos) {
    if (_data == null || _data!.lines.isEmpty) return null;
    int? active;
    for (var i = 0; i < _data!.lines.length; i++) {
      final line = _data!.lines[i];
      if (line.time != null && line.time! <= pos) {
        active = i;
      } else if (line.time != null && line.time! > pos) {
        break;
      }
    }
    return active;
  }

  void _scrollToActiveLine(int index) {
    if (index < 0 || index >= _lineKeys.length) return;
    final key = _lineKeys[index];
    final currentContext = key.currentContext;
    if (currentContext != null) {
      Scrollable.ensureVisible(
        currentContext,
        alignment: 0.4,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Future<void> _loadSong(Song song) async {
    final cached = LyricsService.getCached(song);
    if (cached != null) {
      setState(() {
        _data = cached;
        _loading = false;
        _error = null;
        _setupLineKeys(cached);
        _activeLineIndex = _calculateActiveLine(_audio.currentPosition);
      });
      if (_autoScroll && _activeLineIndex != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToActiveLine(_activeLineIndex!);
        });
      }
    } else if (_data == null) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final data = await _service.fetch(song);
      if (!mounted || _currentSong.id != song.id) return;

      _setupLineKeys(data);
      setState(() {
        _data = data;
        _loading = false;
        _error = null;
        _activeLineIndex = _calculateActiveLine(_audio.currentPosition);
      });

      if (_autoScroll && _activeLineIndex != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToActiveLine(_activeLineIndex!);
        });
      }

      if (_activeLineIndex != null && _activeLineIndex! >= 0 && _activeLineIndex! < data.lines.length) {
        final currentLine = data.lines[_activeLineIndex!].text.trim();
        final nextLine = (_activeLineIndex! + 1 < data.lines.length) ? data.lines[_activeLineIndex! + 1].text.trim() : '';
        final textToShow = nextLine.isNotEmpty ? '$currentLine\n$nextLine' : currentLine;
        await HomeWidgetService.updateLyrics(
          song: '${song.title} · ${song.artist}',
          text: textToShow.isNotEmpty ? textToShow : data.text,
        );
      } else {
        final lines = data.text.split('\n').where((l) => l.trim().isNotEmpty).toList();
        final preview = lines.take(4).join('\n');
        await HomeWidgetService.updateLyrics(
          song: '${song.title} · ${song.artist}',
          text: preview.isNotEmpty ? preview : data.text,
        );
      }
    } catch (error) {
      if (!mounted || _currentSong.id != song.id) return;
      if (_data == null) {
        setState(() {
          _error = error;
          _loading = false;
        });
      }
    }
  }

  void _copyLyrics() {
    if (_data == null) return;
    Clipboard.setData(ClipboardData(text: '${_currentSong.title} - ${_currentSong.artist}\n\n${_data!.text}'));
    LoopinSnackBar.show(context, 'Lyrics copied to clipboard', type: LoopinSnackBarType.success);
  }

  Future<void> _onLineTap(LyricLine line, int index) async {
    if (line.time != null) {
      HapticFeedback.selectionClick();
      await _audio.seek(line.time!);
      setState(() {
        _activeLineIndex = index;
        _autoScroll = true;
      });
      _scrollToActiveLine(index);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text('Lyrics', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        centerTitle: true,
        actions: [
          if (_data != null && _data!.isSynced)
            IconButton(
              icon: Icon(
                _autoScroll ? Icons.sync_rounded : Icons.sync_disabled_rounded,
                color: _autoScroll ? AppColors.accent : AppColors.muted,
                size: 22,
              ),
              tooltip: _autoScroll ? 'Auto-scroll on' : 'Auto-scroll paused',
              onPressed: () {
                setState(() => _autoScroll = !_autoScroll);
                if (_autoScroll && _activeLineIndex != null) {
                  _scrollToActiveLine(_activeLineIndex!);
                }
              },
            ),
          if (_data != null)
            IconButton(
              icon: const Icon(Icons.copy_rounded, size: 20),
              tooltip: 'Copy lyrics',
              onPressed: _copyLyrics,
            ),
          const SizedBox(width: 6),
        ],
      ),
      body: _loading
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: AppColors.accent),
                  SizedBox(height: 16),
                  Text('Fetching synchronized lyrics...', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                ],
              ),
            )
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.lyrics_outlined, size: 54, color: Colors.white24),
                        const SizedBox(height: 16),
                        Text(
                          _error.toString().replaceFirst('Bad state: ', '').replaceFirst('Exception: ', ''),
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppColors.muted, fontSize: 14),
                        ),
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.surfaceElevated,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () => _loadSong(_currentSong),
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: const Text('Try again'),
                        ),
                      ],
                    ),
                  ),
                )
              : Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: NotificationListener<ScrollNotification>(
                      onNotification: (notification) {
                        if (notification is UserScrollNotification) {
                          // If user scrolls manually, keep tracking but allow scrolling
                        }
                        return false;
                      },
                      child: ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 90),
                        itemCount: _data!.lines.length + 2, // Header, Lines..., Footer
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            return _buildHeader();
                          }
                          if (index == _data!.lines.length + 1) {
                            return _buildFooter();
                          }

                          final lineIndex = index - 1;
                          final line = _data!.lines[lineIndex];
                          final isActive = _data!.isSynced && lineIndex == _activeLineIndex;
                          final isPast = _data!.isSynced && _activeLineIndex != null && lineIndex < _activeLineIndex!;

                          return KeyedSubtree(
                            key: _lineKeys[lineIndex],
                            child: _buildLyricLine(line, lineIndex, isActive: isActive, isPast: isPast),
                          );
                        },
                      ),
                    ),
                  ),
                ),
      floatingActionButton: (_data != null && _data!.isSynced && !_autoScroll && _activeLineIndex != null)
          ? FloatingActionButton.extended(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
              onPressed: () {
                setState(() => _autoScroll = true);
                if (_activeLineIndex != null) {
                  _scrollToActiveLine(_activeLineIndex!);
                }
              },
              icon: const Icon(Icons.navigation_rounded, size: 18),
              label: const Text('Sync with song', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
            )
          : null,
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 32, top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            _currentSong.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              height: 1.25,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _currentSong.artist,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.accent,
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),
          if ((_data?.source ?? '').isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _data!.isSynced ? AppColors.accent.withValues(alpha: 0.15) : AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _data!.isSynced ? AppColors.accent.withValues(alpha: 0.4) : Colors.white12,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_data!.isSynced) ...[
                    const Icon(Icons.graphic_eq_rounded, size: 13, color: AppColors.accent),
                    const SizedBox(width: 5),
                  ],
                  Text(
                    _data!.source!,
                    style: TextStyle(
                      color: _data!.isSynced ? AppColors.accent : Colors.white60,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 18),
          const Divider(color: Colors.white10),
        ],
      ),
    );
  }

  Widget _buildLyricLine(
    LyricLine line,
    int index, {
    required bool isActive,
    required bool isPast,
  }) {
    final hasTimestamp = line.time != null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: InkWell(
        onTap: hasTimestamp ? () => _onLineTap(line, index) : null,
        borderRadius: BorderRadius.circular(12),
        splashColor: AppColors.accent.withValues(alpha: 0.1),
        highlightColor: Colors.transparent,
        child: Container(
          width: double.infinity,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeInOut,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: isActive ? 23 : 18,
              fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
              height: 1.65, // Generous line height for Malayalam / Indic glyphs
              letterSpacing: 0.2,
              color: isActive
                  ? AppColors.accent
                  : isPast
                      ? Colors.white.withValues(alpha: 0.3)
                      : Colors.white.withValues(alpha: 0.55),
              // Keep the active lyric clean: accent-pink text with no glow/shadow.
              shadows: null,
            ),
            child: Text(
              line.text,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFooter() {
    if ((_data?.copyright ?? '').trim().isEmpty) {
      return const SizedBox(height: 50);
    }
    return Padding(
      padding: const EdgeInsets.only(top: 40, bottom: 30),
      child: Center(
        child: Text(
          _data!.copyright!,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.35),
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
