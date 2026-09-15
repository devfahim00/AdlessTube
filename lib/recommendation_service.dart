import 'package:newpipeextractor_dart/newpipeextractor_dart.dart'
    show PageToken;

import 'models.dart';
import 'newpipe_service.dart';
import 'storage_service.dart';

/// One endless source the home feed can pull from.
///
/// * [kind] — `channel` (a channel's uploads), `search` (query results) or
///   `related` (videos related to one video).
/// * [weight] — how often the source is polled relative to the others.
class FeedSource {
  final String kind;
  final String key;
  final double weight;
  PageToken? next;
  bool exhausted = false;
  int served = 0;

  FeedSource(this.kind, this.key, this.weight);
}

/// ═══════════════════════ RECOMMENDATIONS ═══════════════════════
///
/// Builds the personalized home feed from every signal the app has about
/// the user:
///
/// * subscribed channels,
/// * channels they watched but did not subscribe to,
/// * channels similar to their subscriptions (discovered in background),
/// * videos related to what they recently watched,
/// * videos related to what they saved,
/// * topics they searched for,
/// * regional trending as discovery filler.
///
/// The feed mixes these with weights instead of a fixed order, so it feels
/// like the official YouTube home feed and keeps evolving as the user
/// searches, watches, saves and subscribes.
class RecommendationService {
  final NewPipeService _service = NewPipeService();

  /// Sources that can be built instantly from local data — no network.
  List<FeedSource> buildLocalSources(StorageService storage) {
    final sources = <FeedSource>[];
    final subscribedUrls = storage.getSubscribedChannelUrls();
    final subscribedSet = subscribedUrls.toSet();

    // 1. Subscribed channels are the backbone of the feed.
    for (final url in subscribedUrls) {
      if (url.isNotEmpty) sources.add(FeedSource('channel', url, 3.0));
    }

    // 2. Videos related to what the user recently watched.
    for (final video in storage.getHistory().take(8)) {
      if (video.url.isNotEmpty) {
        sources.add(FeedSource('related', video.url, 2.5));
      }
    }

    // 3. Saved videos are a strong taste signal too.
    for (final video in storage.getSavedVideos().take(5)) {
      if (video.url.isNotEmpty) {
        sources.add(FeedSource('related', video.url, 1.8));
      }
    }

    // 4. Channels the user watched but did not subscribe to.
    final seenChannels = <String>{};
    for (final video in storage.getHistory()) {
      final url = video.uploaderUrl;
      if (url.isEmpty || subscribedSet.contains(url) || !seenChannels.add(url)) {
        continue;
      }
      sources.add(FeedSource('channel', url, 1.4));
      if (seenChannels.length >= 5) break;
    }

    // 5. Past searches personalise the feed with those topics.
    for (final query in storage.getSearchHistory().take(4)) {
      if (query.trim().isNotEmpty) {
        sources.add(FeedSource('search', query, 1.3));
      }
    }

    // 6. Regional trending keeps the feed alive and diverse for anyone.
    for (final query in _service.trendingQueries(storage.regionCode)) {
      sources.add(FeedSource('search', query, 0.6));
    }
    return sources;
  }

  /// Discovers channels similar to the subscribed ones (but not subscribed)
  /// via channel search. Runs in the background after the feed is already
  /// visible so it never slows down the first load.
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
        final channels = await _service.searchChannels(name);
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

  /// Fetches the next batch of videos from one source, updating its
  /// pagination state. Returns raw items; filtering and deduplication stay
  /// with the caller.
  Future<List<VideoItem>> fetch(FeedSource source) {
    switch (source.kind) {
      case 'related':
        source.exhausted = true; // one-shot
        source.served++;
        return _service.getRelatedVideos(source.key);
      case 'channel':
        return _service
            .getChannelTabPage(source.key, 'videos', next: source.next)
            .then((page) {
          source.served++;
          source.next = page.next;
          if (page.next == null) source.exhausted = true;
          return page.items;
        });
      default:
        return _service
            .searchVideoPage(source.key, next: source.next)
            .then((page) {
          source.served++;
          source.next = page.next;
          if (page.next == null) source.exhausted = true;
          return page.items;
        });
    }
  }

  /// Weighted pick: sources with a higher weight and fewer served pages
  /// come first, mixing subscriptions, recommendations and discovery the
  /// way YouTube's home feed does.
  FeedSource? pickSource(List<FeedSource> sources) {
    FeedSource? best;
    var bestScore = -1.0;
    for (final source in sources) {
      if (source.exhausted) continue;
      final score = source.weight / (source.served + 1);
      if (score > bestScore) {
        bestScore = score;
        best = source;
      }
    }
    return best;
  }
}
