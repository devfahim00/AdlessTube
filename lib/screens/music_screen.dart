import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:newpipeextractor_dart/newpipeextractor_dart.dart'
    show PageToken;
import 'package:provider/provider.dart';

import '../models.dart';
import '../music_playback_service.dart';
import '../newpipe_service.dart';
import '../storage_service.dart';
import '../widgets.dart';
import 'music_player_screen.dart';
import 'music_search_screen.dart';

/// One paginated query the music feed can pull from.
class _MusicSource {
  final String query;
  PageToken? next;
  bool exhausted = false;

  _MusicSource(this.query);
}

/// ═══════════════════════ MUSIC ═══════════════════════
///
/// Spotify-style home: greeting header, quick-access cards and an
/// endless song feed. The album-icon button is gone — while a song
/// plays, a now-playing bar sits above the navbar with a vinyl disc
/// built from the song's own artwork, spinning for as long as the
/// song plays and swapping art the moment the song changes.
class MusicScreen extends StatefulWidget {
  const MusicScreen({super.key});

  @override
  State<MusicScreen> createState() => _MusicScreenState();
}

class _MusicScreenState extends State<MusicScreen> {
  final _service = NewPipeService();
  final List<VideoItem> _songs = [];
  final Set<String> _seen = {};
  final List<_MusicSource> _sources = [];
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  int _cursor = 0;

  @override
  void initState() {
    super.initState();
    _initSources();
    unawaited(_loadInitial());
  }

  void _initSources() {
    final storage = context.read<StorageService>();
    for (final query in _service.musicQueries(
      region: storage.regionCode,
      likedSongs: storage.getLikedSongs(),
    )) {
      _sources.add(_MusicSource(query));
    }
  }

  bool get _hasAvailableSources => _sources.any((s) => !s.exhausted);

  Future<void> _loadInitial() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      await _fill(target: 14);
      if (_songs.isEmpty) {
        throw StateError(
            'Could not load music. Check your connection and pull to retry.');
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Manual refresh only — switching tabs never triggers this.
  Future<void> _refresh() async {
    _songs.clear();
    _seen.clear();
    for (final source in _sources) {
      source.exhausted = false;
      source.next = null;
    }
    await _loadInitial();
  }

  Future<void> _fill({int target = 10}) async {
    var added = 0;
    while (added < target) {
      final source = _nextSource();
      if (source == null) break;
      final count = await _fetchSource(source);
      added += count;
      if (count > 0 && mounted) setState(() {});
    }
  }

  _MusicSource? _nextSource() {
    final alive = _sources.where((s) => !s.exhausted).toList();
    if (alive.isEmpty) return null;
    final source = alive[_cursor % alive.length];
    _cursor++;
    return source;
  }

  Future<int> _fetchSource(_MusicSource source) async {
    try {
      final page = await _service.searchVideoPage(
        source.query,
        next: source.next,
      );
      source.next = page.next;
      if (page.next == null) source.exhausted = true;
      var added = 0;
      for (final song in page.items) {
        if (song.isLive || song.isShort) continue;
        if (_seen.add(song.id)) {
          _songs.add(song);
          added++;
        }
      }
      return added;
    } catch (_) {
      source.exhausted = true;
      return 0;
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || _error != null || !_hasAvailableSources) {
      return;
    }
    setState(() => _loadingMore = true);
    try {
      await _fill(target: 10);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _openSong(VideoItem song, List<VideoItem> queue) async {
    final storage = context.read<StorageService>();
    await storage.addToHistory(song);
    if (!mounted) return;
    context.read<MusicPlaybackService>().setQueue(queue, song);
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => MusicPlayerScreen(song: song)),
    );
  }

  void _openSearch() {
    Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => const MusicSearchScreen()),
    );
  }

  /// Favourites queue loops within itself — no outside songs ever join in.
  Future<void> _showFavorites() async {
    final favorites = context.read<StorageService>().getLikedSongs();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: 420,
          child: favorites.isEmpty
              ? const Center(child: Text('No favourite songs yet'))
              : Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.favorite,
                          color: Color(0xFF1DB954)),
                      title: const Text('Favourite songs'),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: favorites.length,
                        itemBuilder: (_, index) {
                          final song = favorites[index];
                          return ListTile(
                            leading: const Icon(Icons.music_note),
                            title: Text(
                              song.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              song.uploader,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () {
                              Navigator.of(sheetContext).pop();
                              _openSongFromFavorites(favorites, song);
                            },
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

  void _openSongFromFavorites(
      List<VideoItem> favorites, VideoItem song) {
    context.read<MusicPlaybackService>().setQueue(
          favorites,
          song,
          repeat: QueueRepeat.loop,
        );
    unawaited(
      Navigator.push<void>(
        context,
        MaterialPageRoute(builder: (_) => MusicPlayerScreen(song: song)),
      ),
    );
    // History entry is recorded after the push so the sheet closes first.
    unawaited(context.read<StorageService>().addToHistory(song));
  }

  /// Spotify-style time-of-day greeting.
  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  /// Greeting row + quick-access cards + the feed's section title.
  Widget _buildHeader(StorageService storage) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 6, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _greeting(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _openSearch,
                  icon: const Icon(Icons.search),
                  tooltip: 'Search music',
                ),
                IconButton(
                  onPressed: _showFavorites,
                  icon: const Icon(Icons.favorite_outline),
                  tooltip: 'Favourite songs',
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  onSelected: (value) {
                    if (value == 'autoplay') {
                      storage.setMusicAutoplay(!storage.musicAutoplay);
                    } else if (value == 'refresh') {
                      unawaited(_refresh());
                    }
                  },
                  itemBuilder: (_) => [
                    CheckedPopupMenuItem(
                      value: 'autoplay',
                      checked: storage.musicAutoplay,
                      child: const Text('Autoplay related songs'),
                    ),
                    const PopupMenuItem(
                      value: 'refresh',
                      child: Text('Refresh music'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        // Quick access — Spotify's shortcut cards.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: _QuickCard(
                  icon: Icons.favorite,
                  color: const Color(0xFF1DB954),
                  label: 'Favourite songs',
                  onTap: _showFavorites,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _QuickCard(
                  icon: Icons.search,
                  color: const Color(0xFF3E7EDB),
                  label: 'Search music',
                  onTap: _openSearch,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 6),
          child: Text(
            'Songs for you',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    final music = context.watch<MusicPlaybackService>();
    final playingSong = music.song;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // No AppBar here — set the status-bar icon color to match the theme
    // the way an AppBar would.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
      body: _loading
          ? const SafeArea(child: MusicListSkeleton())
          : _error != null
              ? SafeArea(child: ErrorView(message: _error!, onRetry: _refresh))
              : Stack(
                  children: [
                    RefreshIndicator(
                      onRefresh: _refresh,
                      child: NotificationListener<ScrollNotification>(
                        onNotification: (notification) {
                          if (notification.metrics.extentAfter < 600) {
                            unawaited(_loadMore());
                          }
                          return false;
                        },
                        child: ListView.builder(
                          padding: EdgeInsets.only(
                            bottom: playingSong != null ? 176 : 96,
                          ),
                          itemCount: _songs.length + 2,
                          itemBuilder: (context, index) {
                            // Header block: greeting, cards, section title.
                            if (index == 0) return _buildHeader(storage);
                            // Footer: more songs loading / end of feed.
                            if (index == _songs.length + 1) {
                              if (_hasAvailableSources || _loadingMore) {
                                return const Padding(
                                  padding: EdgeInsets.all(20),
                                  child: Center(
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  ),
                                );
                              }
                              return const Padding(
                                padding: EdgeInsets.all(24),
                                child: Center(
                                  child: Text(
                                    'No more songs',
                                    style: TextStyle(color: Colors.grey),
                                  ),
                                ),
                              );
                            }
                            final song = _songs[index - 1];
                            final liked = storage.isSongLiked(song.id);
                            return MusicListTile(
                              song: song,
                              liked: liked,
                              isPlaying: playingSong?.id == song.id,
                              onTap: () => _openSong(song, _songs),
                              onToggleLike: () =>
                                  storage.toggleLikedSong(song),
                            );
                          },
                        ),
                      ),
                    ),
                    // Now-playing bar: a vinyl disc of the current song's
                    // artwork spins above the navbar while music plays.
                    if (playingSong != null)
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(10, 0, 10, 78),
                          child: _NowPlayingBar(
                            song: playingSong,
                            isPlaying: music.isPlaying,
                            onTap: () => Navigator.push<void>(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    MusicPlayerScreen(song: playingSong),
                              ),
                            ),
                            onTogglePlay: () => music.playOrPause(),
                          ),
                        ),
                      ),
                  ],
                ),
      ),
    );
  }
}

/// Spotify shortcut card: colored icon tile + bold label.
class _QuickCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  const _QuickCard({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 58,
          child: Row(
            children: [
              Container(
                width: 58,
                height: 58,
                color: color,
                child: Icon(icon, color: Colors.white, size: 26),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13.5,
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}

/// Spotify-style now-playing bar. Instead of a plain album icon, the
/// current song's thumbnail becomes a vinyl disc that rotates 360°
/// endlessly for as long as the song plays, holds its angle on pause
/// and swaps its artwork the moment the song changes.
class _NowPlayingBar extends StatefulWidget {
  final VideoItem song;
  final bool isPlaying;
  final VoidCallback onTap;
  final VoidCallback onTogglePlay;

  const _NowPlayingBar({
    required this.song,
    required this.isPlaying,
    required this.onTap,
    required this.onTogglePlay,
  });

  @override
  State<_NowPlayingBar> createState() => _NowPlayingBarState();
}

class _NowPlayingBarState extends State<_NowPlayingBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 14),
  );

  @override
  void initState() {
    super.initState();
    if (widget.isPlaying) _spin.repeat();
  }

  @override
  void didUpdateWidget(covariant _NowPlayingBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A song change rebuilds the bar with new artwork — the rotation
    // itself only follows the play/pause state.
    if (widget.isPlaying == oldWidget.isPlaying) return;
    if (widget.isPlaying) {
      _spin.repeat(from: _spin.value);
    } else {
      _spin.stop();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final barColor = isDark
        ? const Color(0xFF2A2A2A)
        : theme.colorScheme.surfaceContainerHighest;
    return Material(
      color: barColor,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      elevation: isDark ? 0 : 3,
      shadowColor: Colors.black26,
      child: InkWell(
        onTap: widget.onTap,
        child: SizedBox(
          height: 60,
          child: Row(
            children: [
              const SizedBox(width: 8),
              RotationTransition(
                turns: _spin,
                child: _VinylDisc(
                  videoId: widget.song.id,
                  fallbackUrl: widget.song.thumbnailUrl,
                  size: 44,
                  holeColor: barColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.song.uploader,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: widget.onTogglePlay,
                icon: Icon(
                  widget.isPlaying ? Icons.pause : Icons.play_arrow,
                  size: 28,
                ),
                tooltip: widget.isPlaying ? 'Pause' : 'Play',
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }
}

/// A spinning record: black vinyl base, the song's artwork as the
/// label and a small center hole.
class _VinylDisc extends StatelessWidget {
  final String videoId;
  final String fallbackUrl;
  final double size;
  final Color holeColor;

  const _VinylDisc({
    required this.videoId,
    required this.fallbackUrl,
    required this.size,
    required this.holeColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final artSize = size - 3;
    final Widget art;
    if (videoId.isEmpty && fallbackUrl.isEmpty) {
      art = Container(
        width: artSize,
        height: artSize,
        color: theme.colorScheme.surfaceContainerHighest,
        child: Icon(Icons.music_note, size: artSize * 0.45),
      );
    } else {
      art = VideoThumbnail(
        videoId: videoId,
        fallbackUrl: fallbackUrl,
        width: artSize,
        height: artSize,
        placeholder: Container(
          width: artSize,
          height: artSize,
          color: theme.colorScheme.surfaceContainerHighest,
        ),
        errorWidget: Container(
          width: artSize,
          height: artSize,
          color: theme.colorScheme.surfaceContainerHighest,
          child: Icon(Icons.music_note, size: artSize * 0.45),
        ),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.black87,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          ClipOval(child: art),
          Container(
            width: size * 0.15,
            height: size * 0.15,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: holeColor,
              border: Border.all(color: Colors.black54, width: 0.8),
            ),
          ),
        ],
      ),
    );
  }
}
