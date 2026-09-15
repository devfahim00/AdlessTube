import 'dart:async';

import 'package:flutter/material.dart';
import 'package:newpipeextractor_dart/newpipeextractor_dart.dart'
    show PageToken;
import 'package:provider/provider.dart';

import '../models.dart';
import '../newpipe_service.dart';
import '../region_service.dart';
import '../storage_service.dart';
import '../widgets.dart';
import 'player_screen.dart';
import 'search_screen.dart';

/// One paginated source the home feed can pull from.
class _FeedSource {
  /// search | channel | related
  final String kind;
  final String key;
  PageToken? next;
  bool exhausted = false;

  _FeedSource(this.kind, this.key);
}

/// ═══════════════════════ HOME ═══════════════════════
///
/// YouTube-style feed: big tiles, skeleton loading and endless content —
/// new videos keep loading as long as the user keeps scrolling.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _service = NewPipeService();
  final List<VideoItem> _feed = [];
  final Set<String> _seen = {};
  final List<_FeedSource> _sources = [];
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
    for (final url in storage.getSubscribedChannelUrls()) {
      _sources.add(_FeedSource('channel', url));
    }
    for (final query in _service.trendingQueries(storage.regionCode)) {
      _sources.add(_FeedSource('search', query));
    }
    // Recent watches personalise the feed with related videos.
    for (final video in storage.getHistory().take(3)) {
      if (video.url.isNotEmpty) _sources.add(_FeedSource('related', video.url));
    }
  }

  bool get _hasAvailableSources => _sources.any((s) => !s.exhausted);

  Future<void> _loadInitial() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _fill(target: 14);
      if (_feed.isEmpty) {
        throw StateError(
            'Could not load the home feed. Check your connection and pull to retry.');
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Manual refresh only — switching tabs never triggers this.
  Future<void> _refresh() async {
    _feed.clear();
    _seen.clear();
    for (final source in _sources) {
      source.exhausted = false;
      source.next = null;
    }
    await _loadInitial();
  }

  /// Keeps fetching from the available sources until [target] new videos
  /// have been added (or every source is exhausted).
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

  /// Round-robin through the sources so the feed stays mixed.
  _FeedSource? _nextSource() {
    final alive = _sources.where((s) => !s.exhausted).toList();
    if (alive.isEmpty) return null;
    final source = alive[_cursor % alive.length];
    _cursor++;
    return source;
  }

  Future<int> _fetchSource(_FeedSource source) async {
    try {
      switch (source.kind) {
        case 'related':
          source.exhausted = true; // one-shot
          final videos = await _service.getRelatedVideos(source.key);
          return _addUnique(videos);
        case 'channel':
          final page = await _service.getChannelTabPage(
            source.key,
            'videos',
            next: source.next,
          );
          source.next = page.next;
          if (page.next == null) source.exhausted = true;
          return _addUnique(page.items);
        default:
          final page = await _service.searchVideoPage(
            source.key,
            next: source.next,
          );
          source.next = page.next;
          if (page.next == null) source.exhausted = true;
          return _addUnique(page.items);
      }
    } catch (_) {
      source.exhausted = true;
      return 0;
    }
  }

  int _addUnique(List<VideoItem> videos) {
    var added = 0;
    for (final video in videos) {
      if (video.isLive || video.isShort) continue;
      if (_seen.add(video.id)) {
        _feed.add(video);
        added++;
      }
    }
    return added;
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

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    final region = storage.regionCode;
    final flag = RegionService.flagFor(region);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('AdlessTube'),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.grey[800],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text('$flag $region',
                  style: const TextStyle(fontSize: 12)),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SearchScreen()),
            ),
          ),
        ],
      ),
      body: _loading
          ? const VideoFeedSkeleton()
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
                      itemCount: _feed.length + 1,
                      itemBuilder: (context, index) {
                        if (index == _feed.length) {
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
                                'No more videos',
                                style: TextStyle(color: Colors.grey),
                              ),
                            ),
                          );
                        }
                        final video = _feed[index];
                        return YouTubeVideoTile(
                          video: video,
                          onTap: () async {
                            await storage.addToHistory(video);
                            if (context.mounted) {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) =>
                                        PlayerScreen(video: video)),
                              );
                            }
                          },
                        );
                      },
                    ),
                  ),
                ),
    );
  }
}
