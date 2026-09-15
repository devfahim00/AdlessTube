import 'dart:async';

import 'package:flutter/material.dart';
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
/// Skeleton loading + endless feed: new songs keep loading while the
/// user keeps scrolling.
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
                    const ListTile(
                      leading: Icon(Icons.favorite, color: Colors.red),
                      title: Text('Favourite songs'),
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

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    final music = context.watch<MusicPlaybackService>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Music'),
        actions: [
          IconButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MusicSearchScreen()),
            ),
            icon: const Icon(Icons.search),
            tooltip: 'Search music',
          ),
          IconButton(
            onPressed: _showFavorites,
            icon: const Icon(Icons.favorite_outline),
            tooltip: 'Favourite songs',
          ),
          IconButton(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh music',
          ),
          PopupMenuButton<bool>(
            icon: const Icon(Icons.more_vert),
            onSelected: storage.setMusicAutoplay,
            itemBuilder: (_) => [
              CheckedPopupMenuItem(
                value: !storage.musicAutoplay,
                checked: storage.musicAutoplay,
                child: const Text('Autoplay related songs'),
              ),
            ],
          ),
        ],
      ),
      body: _loading
          ? const MusicListSkeleton()
          : _error != null
              ? ErrorView(message: _error!, onRetry: _refresh)
              : RefreshIndicator(
                  onRefresh: _refresh,
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (notification) {
                      if (notification.metrics.extentAfter < 600) {
                        unawaited(_loadMore());
                      }
                      return false;
                    },
                    child: ListView.builder(
                      padding: const EdgeInsets.only(bottom: 96),
                      itemCount: _songs.length + 1,
                      itemBuilder: (context, index) {
                        if (index == _songs.length) {
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
                        final song = _songs[index];
                        final liked = storage.isSongLiked(song.id);
                        return MusicListTile(
                          song: song,
                          liked: liked,
                          onTap: () => _openSong(song, _songs),
                          onToggleLike: () =>
                              storage.toggleLikedSong(song),
                        );
                      },
                    ),
                  ),
                ),
      floatingActionButton: music.isPlaying && music.song != null
          ? Padding(
              padding: const EdgeInsets.only(bottom: 72),
              child: FloatingActionButton.small(
                tooltip: 'Open now playing',
                child: const Icon(Icons.album),
                onPressed: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MusicPlayerScreen(song: music.song!),
                  ),
                ),
              ),
            )
          : null,
    );
  }
}
