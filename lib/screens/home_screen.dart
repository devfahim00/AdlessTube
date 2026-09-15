import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../recommendation_service.dart';
import '../region_service.dart';
import '../storage_service.dart';
import '../widgets.dart';
import 'player_screen.dart';
import 'search_screen.dart';

/// ═══════════════════════ HOME ═══════════════════════
///
/// Personalized YouTube-style feed:
/// * big tiles with thumbnails, titles and channel avatars,
/// * skeleton loading and endless content while scrolling,
/// * sources mixed by weight from everything the user did in the app —
///   subscriptions, watch history, saved videos, past searches,
///   watched-but-unsubscribed channels, similar channels and trending.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _recommendations = RecommendationService();
  final List<VideoItem> _feed = [];
  final Set<String> _seen = {};
  Set<String> _watchedIds = {};
  List<FeedSource> _sources = [];
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  bool _discovering = false;

  @override
  void initState() {
    super.initState();
    _initSources();
    unawaited(_loadInitial());
  }

  void _initSources() {
    final storage = context.read<StorageService>();
    // Recently watched videos are not repeated in the feed.
    _watchedIds = storage.getHistory().map((v) => v.id).toSet();
    _sources = _recommendations.buildLocalSources(storage);
    unawaited(_discoverSimilar());
  }

  /// Background discovery of channels related to the user's subscriptions.
  /// The feed is already usable while this runs; discovered sources simply
  /// join the mix afterwards.
  Future<void> _discoverSimilar() async {
    if (_discovering) return;
    _discovering = true;
    try {
      final found = await _recommendations.discoverSimilarChannels(
        context.read<StorageService>(),
        existing: _sources,
      );
      if (found.isNotEmpty && mounted) {
        setState(() => _sources.addAll(found));
      }
    } finally {
      _discovering = false;
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

  /// Manual refresh only — switching tabs never triggers this. Refreshing
  /// rebuilds the recommendation sources so new watches, saves, searches and
  /// subscriptions immediately change the mix.
  Future<void> _refresh() async {
    _feed.clear();
    _seen.clear();
    _initSources();
    await _loadInitial();
  }

  /// Keeps fetching from the available sources until [target] new videos
  /// have been added (or every source is exhausted).
  Future<void> _fill({int target = 10}) async {
    var added = 0;
    while (added < target) {
      final source = _recommendations.pickSource(_sources);
      if (source == null) break;
      final count = await _fetchSource(source);
      added += count;
      if (count > 0 && mounted) setState(() {});
    }
  }

  Future<int> _fetchSource(FeedSource source) async {
    try {
      final videos = await _recommendations.fetch(source);
      return _addUnique(videos);
    } catch (_) {
      source.exhausted = true;
      return 0;
    }
  }

  int _addUnique(List<VideoItem> videos) {
    var added = 0;
    for (final video in videos) {
      if (video.isLive || video.isShort) continue;
      // Never repeat something the user already watched.
      if (_watchedIds.contains(video.id)) continue;
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
