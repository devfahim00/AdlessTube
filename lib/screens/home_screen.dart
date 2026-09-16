import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../models.dart';
import '../recommendation_service.dart';
import '../region_service.dart';
import '../storage_service.dart';
import '../user_profile_service.dart';
import '../widgets.dart';
import 'player_screen.dart';
import 'search_screen.dart';

/// ═══════════════════════ HOME ═══════════════════════
///
/// YouTube-style personalized home, driven by the on-device user
/// profile (watch percentages, channel affinity, topic taste):
///
/// * filter chips — For you / Trending / Subscriptions,
/// * a "From your subscriptions" shelf with fresh uploads,
/// * the "For you" feed: candidates fetched from profile-chosen
///   sources, **scored** by the profile and rendered in rank order
///   with channel-diversity limits,
/// * a three-dot menu on every tile — "Not interested" and "Don't
///   recommend channel" feed straight back into the profile,
/// * skeleton loading and endless content while scrolling.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _recommendations = RecommendationService();

  // ── Ranked feed state ──
  final List<VideoItem> _feed = [];
  final Set<String> _seen = {};
  final List<_ScoredCandidate> _candidates = [];
  final Set<String> _candidateIds = {};
  Set<String> _watchedIds = {};
  Set<String> _recentlyShown = {};
  final Set<String> _newShown = {};
  List<FeedSource> _sources = [];
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  bool _discovering = false;
  late final StorageService _storage;
  late final UserProfileService _profile;

  // ── Filter chips ──
  static const _chips = [('all', 'For you'), ('trending', 'Trending'), ('subs', 'Subscriptions')];
  String _activeChip = 'all';

  // ── Trending chip ──
  List<VideoItem> _trending = [];
  bool _trendingLoading = false;
  String? _trendingError;

  // ── Subscriptions (shelf + chip) ──
  List<VideoItem> _subUploads = [];
  bool _subsLoading = false;

  // ── Channel diversity ──
  // The feed never shows more than [_channelMaxInWindow] videos from one
  // channel inside the last [_channelWindow] items, so a single source
  // (one subscription, one related list) can never dump 10+ videos from
  // the same channel back to back.
  static const _channelWindow = 8;
  static const _channelMaxInWindow = 2;
  final List<String> _recentUploaders = [];

  @override
  void initState() {
    super.initState();
    _storage = context.read<StorageService>();
    _profile = context.read<UserProfileService>();
    _initSources();
    unawaited(_loadInitial());
    unawaited(_loadSubUploads());
  }

  void _initSources() {
    // Recently watched videos are not repeated in the feed, and neither
    // are videos the feed recently showed — refresh must change it.
    _watchedIds = _storage.getHistory().map((v) => v.id).toSet();
    _recentlyShown = _storage.getShownFeedIds().difference(_watchedIds);
    _sources = _recommendations.buildSources(_storage, _profile);
    unawaited(_discoverSimilar());
  }

  /// Background discovery of channels related to the user's
  /// subscriptions. The feed is already usable while this runs;
  /// discovered sources simply join the mix afterwards.
  Future<void> _discoverSimilar() async {
    if (_discovering) return;
    _discovering = true;
    try {
      final found = await _recommendations.discoverSimilarChannels(
        _storage,
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

  // ─────────────────── For you: load / refresh ───────────────────

  Future<void> _loadInitial() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _fill(target: 14);
      if (_feed.isEmpty) {
        // Everything might be filtered out by the seen-memory (fresh
        // install with lots of history) — retry once without it.
        _recentlyShown = {};
        await _fill(target: 14);
      }
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

  /// Manual refresh only. Rebuilds the taste profile from the newest
  /// signals (so a just-finished video already moves the feed), then
  /// rebuilds the sources and skips what was already shown.
  Future<void> _refresh() async {
    switch (_activeChip) {
      case 'trending':
        await _loadTrending(force: true);
      case 'subs':
        await _loadSubUploads(force: true);
      default:
        await _profile.rebuildProfile();
        _feed.clear();
        _seen.clear();
        _newShown.clear();
        _candidates.clear();
        _candidateIds.clear();
        _recentUploaders.clear();
        _initSources();
        await _loadInitial();
        unawaited(_loadSubUploads(force: true));
    }
  }

  // ─────────────────── For you: ranking pipeline ───────────────────

  /// Keeps fetching from the available sources until [target] ranked
  /// videos have been emitted. Fetched items are scored by the profile
  /// into a candidate pool; [_emitRanked] then serves them in score
  /// order with diversity limits.
  Future<void> _fill({int target = 10}) async {
    var added = _emitRanked(target);
    if (added > 0 && mounted) setState(() {});
    var attempts = 0;
    while (added < target && attempts < 26 && _hasAvailableSources) {
      final source = _recommendations.pickSource(_sources);
      if (source == null) break;
      attempts++;
      try {
        await _recommendations.fetch(source);
      } catch (_) {
        source.queue.clear();
        source.exhausted = true;
      }
      _absorbQueue(source.queue);
      added += _emitRanked(target - added);
      if (added > 0 && mounted) setState(() {});
    }
    _persistShown();
  }

  /// Moves a fetched queue into the scored candidate pool, dropping
  /// everything the profile rejects.
  void _absorbQueue(List<VideoItem> queue) {
    while (queue.isNotEmpty) {
      final video = queue.removeAt(0);
      if (_eligible(video)) {
        _candidates.add(_ScoredCandidate(video, _profile.scoreVideo(video)));
        _candidateIds.add(video.id);
      }
    }
  }

  bool _eligible(VideoItem video) {
    if (video.isLive || video.isShort) return false;
    if (video.id.isEmpty) return false;
    // Never repeat something the user already watched…
    if (_watchedIds.contains(video.id)) return false;
    // …nor anything the feed showed recently…
    if (_recentlyShown.contains(video.id)) return false;
    // …nor duplicates already in the pool or the feed.
    if (_seen.contains(video.id)) return false;
    if (_candidateIds.contains(video.id)) return false;
    // Explicit feedback: hidden videos and blocked channels are gone.
    if (_profile.isVideoHidden(video.id)) return false;
    if (video.uploaderUrl.isNotEmpty &&
        _profile.isChannelBlocked(video.uploaderUrl)) {
      return false;
    }
    return true;
  }

  /// Serves up to [max] candidates in score order. Videos whose channel
  /// is over-represented in the recent window are held back and only
  /// served when the diversity rule would otherwise leave the feed
  /// short (a repetitive feed still beats an empty one).
  int _emitRanked(int max) {
    if (max <= 0 || _candidates.isEmpty) return 0;
    _candidates.sort((a, b) => b.score.compareTo(a.score));
    var count = 0;
    final heldBack = <_ScoredCandidate>[];
    final leftovers = <_ScoredCandidate>[];
    for (final candidate in _candidates) {
      if (count >= max) {
        leftovers.add(candidate);
      } else if (_channelTiring(candidate.video)) {
        heldBack.add(candidate);
      } else {
        _accept(candidate.video);
        count++;
      }
    }
    for (final candidate in heldBack) {
      if (count >= max) {
        leftovers.add(candidate);
        continue;
      }
      _accept(candidate.video);
      count++;
    }
    _candidates
      ..clear()
      ..addAll(leftovers);
    return count;
  }

  void _accept(VideoItem video) {
    _seen.add(video.id);
    _feed.add(video);
    _newShown.add(video.id);
    _rememberUploader(video);
  }

  /// True when [video]'s channel already fills its diversity quota in
  /// the recent window — the item should be held back for now.
  bool _channelTiring(VideoItem video) {
    final url = video.uploaderUrl;
    if (url.isEmpty) return false;
    var hits = 0;
    for (final uploader in _recentUploaders) {
      if (uploader == url) hits++;
    }
    return hits >= _channelMaxInWindow;
  }

  void _rememberUploader(VideoItem video) {
    if (video.uploaderUrl.isEmpty) return;
    _recentUploaders.add(video.uploaderUrl);
    if (_recentUploaders.length > _channelWindow) {
      _recentUploaders.removeAt(0);
    }
  }

  void _persistShown() {
    if (_newShown.isEmpty) return;
    final ids = _newShown.toList();
    _newShown.clear();
    _recentlyShown.addAll(ids);
    unawaited(_storage.rememberShownFeedIds(ids));
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

  // ─────────────────── Trending / Subscriptions chips ───────────────────

  Future<void> _loadTrending({bool force = false}) async {
    if (_trending.isNotEmpty && !force) return;
    setState(() {
      _trendingLoading = true;
      _trendingError = null;
    });
    try {
      final items = await _recommendations.fetchTrending(_storage.regionCode);
      final filtered =
          items.where((v) => !v.isLive && !v.isShort && v.id.isNotEmpty).toList();
      if (!mounted) return;
      if (filtered.isEmpty) {
        setState(() => _trendingError =
            'Could not load trending. Check your connection and pull to retry.');
      } else {
        setState(() => _trending = filtered);
      }
    } catch (_) {
      if (mounted) {
        setState(() =>
            _trendingError = 'Could not load trending. Check your connection and pull to retry.');
      }
    } finally {
      if (mounted) setState(() => _trendingLoading = false);
    }
  }

  Future<void> _loadSubUploads({bool force = false}) async {
    if (_subUploads.isNotEmpty && !force) return;
    if (_storage.getSubscribedChannelUrls().isEmpty) {
      // Unsubscribed from everything — clear the stale shelf/list.
      if (_subUploads.isNotEmpty && mounted) {
        setState(() => _subUploads = []);
      }
      return;
    }
    setState(() => _subsLoading = true);
    try {
      final items = await _recommendations.fetchSubscriptionUploads(_storage);
      if (mounted) setState(() => _subUploads = items);
    } catch (_) {
      // The shelf is optional — a failed fetch never breaks the feed.
    } finally {
      if (mounted) setState(() => _subsLoading = false);
    }
  }

  void _switchChip(String chip) {
    if (_activeChip == chip) return;
    setState(() => _activeChip = chip);
    if (chip == 'trending') unawaited(_loadTrending());
    if (chip == 'subs') unawaited(_loadSubUploads());
  }

  // ─────────────────── Tile menu (feedback) ───────────────────

  Future<void> _openVideo(VideoItem video) async {
    await _storage.addToHistory(video);
    if (!mounted) return;
    await Navigator.push(
      context,
      pushPlayerRoute(
        PlayerScreen(video: video),
        animationsEnabled: _storage.animationsEnabled,
      ),
    );
  }

  Future<void> _showVideoMenu(VideoItem video, {int feedIndex = -1}) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppTheme.sheetBackground(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
              child: Text(
                video.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.visibility_off),
              title: const Text('Not interested'),
              subtitle: const Text("Won't show this video again"),
              onTap: () => Navigator.pop(sheetContext, 'ni'),
            ),
            ListTile(
              leading: const Icon(Icons.person_off_outlined),
              title: const Text("Don't recommend channel"),
              subtitle: Text(video.uploader),
              onTap: () => Navigator.pop(sheetContext, 'block'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    final messenger = ScaffoldMessenger.of(context);
    if (action == 'ni') {
      await _profile.markNotInterested(video);
      if (!mounted) return;
      setState(() {
        _feed.removeWhere((v) => v.id == video.id);
        _trending.removeWhere((v) => v.id == video.id);
        _subUploads.removeWhere((v) => v.id == video.id);
        _candidates.removeWhere((c) => c.video.id == video.id);
        _candidateIds.remove(video.id);
      });
      messenger.showSnackBar(
        SnackBar(
          content: const Text('Video removed'),
          action: SnackBarAction(
            label: 'UNDO',
            onPressed: () async {
              await _profile.undoNotInterested(video.id);
              if (!mounted) return;
              setState(() {
                final index = feedIndex >= 0 && feedIndex <= _feed.length
                    ? feedIndex
                    : _feed.length;
                _feed.insert(index, video);
              });
            },
          ),
        ),
      );
    } else if (action == 'block') {
      final channelUrl = video.uploaderUrl;
      await _profile.blockChannel(channelUrl, video.uploader);
      if (!mounted) return;
      setState(() {
        _feed.removeWhere((v) => v.uploaderUrl == channelUrl);
        _trending.removeWhere((v) => v.uploaderUrl == channelUrl);
        _subUploads.removeWhere((v) => v.uploaderUrl == channelUrl);
        _candidates.removeWhere((c) => c.video.uploaderUrl == channelUrl);
      });
      messenger.showSnackBar(
        SnackBar(
          content: Text("You won't see ${video.uploader} in your feed"),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  // ─────────────────── Build ───────────────────

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    final region = storage.regionCode;
    final flag = RegionService.flagFor(region);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('AdlessTube'),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHigh,
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
      body: Column(
        children: [
          // Filter chips — YouTube-style top row.
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: [
                for (final (value, label) in _chips)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(label),
                      selected: _activeChip == value,
                      onSelected: (_) => _switchChip(value),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: switch (_activeChip) {
              'trending' => _buildTrending(),
              'subs' => _buildSubscriptions(),
              _ => _buildForYou(),
            },
          ),
        ],
      ),
    );
  }

  Widget _buildForYou() {
    if (_loading) return const VideoFeedSkeleton();
    if (_error != null) return ErrorView(message: _error!, onRetry: _refresh);
    final hasShelf = _subUploads.isNotEmpty;
    return RefreshIndicator(
      onRefresh: _refresh,
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification.metrics.extentAfter < 600) {
            unawaited(_loadMore());
          }
          return false;
        },
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 96),
          itemCount: _feed.length + (hasShelf ? 1 : 0) + 1,
          itemBuilder: (context, index) {
            if (hasShelf && index == 0) return _buildSubsShelf();
            final feedIndex = index - (hasShelf ? 1 : 0);
            if (feedIndex == _feed.length) {
              if (_hasAvailableSources || _loadingMore) {
                return const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
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
            final video = _feed[feedIndex];
            return YouTubeVideoTile(
              video: video,
              onTap: () => unawaited(_openVideo(video)),
              onMenuPressed: () =>
                  unawaited(_showVideoMenu(video, feedIndex: feedIndex)),
            );
          },
        ),
      ),
    );
  }

  /// Horizontal shelf with the freshest uploads from the channels the
  /// user subscribed to — the "latest from your subscriptions" strip.
  Widget _buildSubsShelf() {
    final theme = Theme.of(context);
    final shelf = _subUploads.take(12).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Row(
            children: [
              Icon(Icons.subscriptions_outlined,
                  size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Text(
                'From your subscriptions',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 216,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: shelf.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final video = shelf[index];
              return _ShelfTile(
                video: video,
                onTap: () => unawaited(_openVideo(video)),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildTrending() {
    if (_trendingLoading && _trending.isEmpty) {
      return const VideoFeedSkeleton();
    }
    if (_trendingError != null && _trending.isEmpty) {
      return ErrorView(message: _trendingError!, onRetry: () => _loadTrending(force: true));
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 96),
        itemCount: _trending.length + 1,
        itemBuilder: (context, index) {
          if (index == _trending.length) {
            if (_trendingLoading) {
              return const Padding(
                padding: EdgeInsets.all(20),
                child: Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              );
            }
            return const SizedBox(height: 8);
          }
          final video = _trending[index];
          return YouTubeVideoTile(
            video: video,
            onTap: () => unawaited(_openVideo(video)),
            onMenuPressed: () => unawaited(_showVideoMenu(video)),
          );
        },
      ),
    );
  }

  Widget _buildSubscriptions() {
    if (_subsLoading && _subUploads.isEmpty) {
      return const VideoFeedSkeleton();
    }
    if (_subUploads.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(32),
          children: [
            Icon(Icons.subscriptions_outlined,
                size: 56, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              'No subscriptions yet',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Subscribe to channels and their latest videos will show up here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 96),
        itemCount: _subUploads.length + (_subsLoading ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _subUploads.length) {
            return const Padding(
              padding: EdgeInsets.all(20),
              child: Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }
          final video = _subUploads[index];
          return YouTubeVideoTile(
            video: video,
            onTap: () => unawaited(_openVideo(video)),
            onMenuPressed: () => unawaited(_showVideoMenu(video)),
          );
        },
      ),
    );
  }
}

/// A candidate video together with its profile score — the feed's
/// ranking unit.
class _ScoredCandidate {
  final VideoItem video;
  final double score;
  const _ScoredCandidate(this.video, this.score);
}

/// Compact card for the subscriptions shelf: fixed width, 16:9
/// thumbnail, two-line title and the channel name.
class _ShelfTile extends StatelessWidget {
  final VideoItem video;
  final VoidCallback onTap;

  const _ShelfTile({required this.video, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 168,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Stack(
                children: [
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: VideoThumbnail(
                      videoId: video.id,
                      fallbackUrl: video.thumbnailUrl,
                      placeholder: Container(
                        color: theme.colorScheme.surfaceContainerHighest,
                      ),
                      errorWidget: Container(
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: const Icon(Icons.broken_image, size: 32),
                      ),
                    ),
                  ),
                  if (video.duration != null && video.duration!.inSeconds > 0)
                    Positioned(
                      right: 5,
                      bottom: 5,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 2),
                          child: Text(
                            formatDuration(video.duration!),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text(
                video.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 3),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text(
                video.uploader,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
