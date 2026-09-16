import 'dart:math';

import 'package:newpipeextractor_dart/newpipeextractor_dart.dart'
    show PageToken;

import 'models.dart';
import 'newpipe_service.dart';
import 'storage_service.dart';
import 'user_profile_service.dart';

/// One endless source the home feed can pull from.
///
/// * [kind] — `channel` (a channel's uploads), `search` (query results) or
///   `related` (videos related to one video).
/// * [weight] — how often the source is polled relative to the others.
/// * [queue] — fetched-but-unserved videos; the feed drains the scored
///   candidate pool, and empty queues trigger the next page fetch.
class FeedSource {
  final String kind;
  final String key;
  final double weight;
  PageToken? next;
  bool exhausted = false;
  int served = 0;
  final List<VideoItem> queue = [];

  FeedSource(this.kind, this.key, this.weight);
}

/// ═══════════════════════ RECOMMENDATIONS ═══════════════════════
///
/// Transport + candidate layer of the personalized home feed. The
/// *taste* lives in [UserProfileService] (channel affinity + topic
/// weights with a 7-day half-life); this service decides **what to
/// fetch** and delivers raw candidates:
///
/// * subscribed channels (the backbone),
/// * videos related to what the user *actually watched* — ranked by
///   watch percentage × decay, not just "last opened",
/// * searches for the strongest positive topic keywords,
/// * high-affinity channels the user never subscribed to,
/// * one saved video's related list (a strong taste hint),
/// * past searches and regional trending as discovery filler,
/// * similar channels discovered from the subscriptions.
///
/// The home screen then scores every candidate through
/// [UserProfileService.scoreVideo] and renders the ranking — this class
/// never decides order, only supply.
class RecommendationService {
  final NewPipeService _service = NewPipeService();
  final Random _random = Random();

  /// A single source fetch may never hang the feed.
  static const _fetchTimeout = Duration(seconds: 18);

  /// Builds every source from the current profile. Local and instant —
  /// network fetches happen later, page by page, while the feed is
  /// already visible.
  List<FeedSource> buildSources(
    StorageService storage,
    UserProfileService profile,
  ) {
    final sources = <FeedSource>[];

    // 1. Subscribed channels are the backbone of the feed.
    for (final url in storage.getSubscribedChannelUrls()) {
      if (url.isNotEmpty) sources.add(FeedSource('channel', url, 3.0));
    }

    // 2. Related to the videos the user genuinely watched (watch% ×
    //    decay ranked). A rotating sample of the best seeds keeps the
    //    feed from echoing one video's related list forever.
    final watchSeeds = profile.bestRecentWatchUrls(12)..shuffle(_random);
    for (final url in watchSeeds.take(3)) {
      sources.add(FeedSource('related', url, 2.4));
    }

    // 3. The strongest positive topics from the taste model — search
    //    weight scales with how strongly the user likes the topic.
    for (final topic in profile.topTopics(6)) {
      final match = profile.topicMatch(topic); // 0..1
      sources.add(FeedSource('search', topic, 1.2 + match * 0.6));
    }

    // 4. High-affinity channels the user watches but never subscribed
    //    to — the "you keep coming back to this one" signal.
    for (final url in profile.highAffinityChannels(4)) {
      sources.add(FeedSource('channel', url, 1.4));
    }

    // 5. One random saved video's related list (explicit taste).
    final saved = storage.getSavedVideos().take(6).toList()..shuffle(_random);
    for (final video in saved.take(1)) {
      if (video.url.isNotEmpty) {
        sources.add(FeedSource('related', video.url, 1.5));
      }
    }

    // 6. Past searches personalise the feed with those intents.
    final searches =
        storage.getSearchHistory().take(6).toList()..shuffle(_random);
    for (final query in searches.take(2)) {
      if (query.trim().isNotEmpty) {
        sources.add(FeedSource('search', query, 1.2));
      }
    }

    // 7. Regional trending keeps the feed alive for anyone — smaller
    //    weight, but always present so discovery never dies.
    final trending = _service.trendingQueries(storage.regionCode)
      ..shuffle(_random);
    final trendingWeight = sources.isEmpty ? 1.6 : 0.7;
    for (final query in trending.take(sources.isEmpty ? 4 : 2)) {
      sources.add(FeedSource('search', query, trendingWeight));
    }
    return sources;
  }

  /// Discovers channels similar to the subscribed ones (but not
  /// subscribed) via channel search. Runs in the background after the
  /// feed is already visible so it never slows down the first load.
  Future<List<FeedSource>> discoverSimilarChannels(
    StorageService storage, {
    List<FeedSource> existing = const [],
  }) async {
    final subscribedSet = storage.getSubscribedChannelUrls().toSet();
    final known = existing.map((s) => s.key).toSet();
    final found = <FeedSource>[];
    for (final name in storage.getSubscribedChannelNames().take(3)) {
      if (name.trim().isEmpty) continue;
      try {
        final channels =
            await _service.searchChannels(name).timeout(_fetchTimeout);
        for (final channel in channels.take(3)) {
          if (channel.url.isEmpty || subscribedSet.contains(channel.url)) {
            continue;
          }
          if (known.contains(channel.url)) continue;
          known.add(channel.url);
          found.add(FeedSource('channel', channel.url, 1.1));
        }
      } catch (_) {}
    }
    return found;
  }

  /// Fresh uploads from every subscribed channel, interleaved one video
  /// per channel per pass (each channel page is newest-first). Powers
  /// both the subscriptions shelf on the home feed and the full
  /// Subscriptions tab.
  Future<List<VideoItem>> fetchSubscriptionUploads(
    StorageService storage, {
    int perChannel = 3,
    int maxChannels = 30,
  }) async {
    final urls = storage.getSubscribedChannelUrls().take(maxChannels).toList();
    final queues = <List<VideoItem>>[];
    // Fetch in small parallel batches so thirty subscriptions do not
    // take thirty sequential round-trips.
    const batchSize = 6;
    for (var i = 0; i < urls.length; i += batchSize) {
      final batch = urls.skip(i).take(batchSize).toList();
      final pages = await Future.wait(
        batch.map((url) async {
          try {
            final page = await _service
                .getChannelTabPage(url, 'videos')
                .timeout(_fetchTimeout);
            return page.items
                .where((v) => !v.isLive && !v.isShort && v.id.isNotEmpty)
                .toList();
          } catch (_) {
            return const <VideoItem>[];
          }
        }),
      );
      queues.addAll(pages);
    }
    // Round-robin interleave: shelf order mixes channels instead of
    // dumping one channel's uploads in a block.
    final merged = <VideoItem>[];
    var index = 0;
    var progress = true;
    while (progress) {
      progress = false;
      for (final queue in queues) {
        if (index < queue.length && index < perChannel) {
          merged.add(queue[index]);
          progress = true;
        }
      }
      index++;
    }
    return merged;
  }

  /// Regional trending videos for the Trending chip.
  Future<List<VideoItem>> fetchTrending(String region) =>
      _service.getTrending(region: region);

  /// Fetches the next page from one source into its queue. The caller
  /// then absorbs the queue into the scored candidate pool. Never
  /// throws — a failed source is marked exhausted and the feed moves on.
  Future<void> fetch(FeedSource source) async {
    switch (source.kind) {
      case 'related':
        source.exhausted = true; // one-shot
        source.served++;
        final items = await _service
            .getRelatedVideos(source.key)
            .timeout(_fetchTimeout);
        // Shuffle related lists: they are already-familiar rankings and
        // the feed should not repeat their exact order every refresh.
        items.shuffle(_random);
        source.queue.addAll(items);
      case 'channel':
        final page = await _service
            .getChannelTabPage(source.key, 'videos', next: source.next)
            .timeout(_fetchTimeout);
        source.served++;
        source.next = page.next;
        if (page.next == null) source.exhausted = true;
        source.queue.addAll(page.items);
      default:
        final page = await _service
            .searchVideoPage(source.key, next: source.next)
            .timeout(_fetchTimeout);
        source.served++;
        source.next = page.next;
        if (page.next == null) source.exhausted = true;
        source.queue.addAll(page.items);
    }
  }

  /// Weighted *lottery* pick — unlike a deterministic max this mixes
  /// sources in fresh proportions every refresh. A source's odds fall
  /// as it serves more pages.
  FeedSource? pickSource(List<FeedSource> sources) {
    final alive = sources.where((s) => !s.exhausted).toList();
    if (alive.isEmpty) return null;

    final weights = [
      for (final s in alive) s.weight / (s.served + 1),
    ];
    var total = 0.0;
    for (final w in weights) {
      total += w;
    }
    if (total <= 0) return alive.first;

    var roll = _random.nextDouble() * total;
    for (var i = 0; i < alive.length; i++) {
      roll -= weights[i];
      if (roll <= 0) return alive[i];
    }
    return alive.last;
  }
}
