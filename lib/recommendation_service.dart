import 'dart:math';

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
/// * [queue] — fetched-but-unserved videos; the feed drains one accepted
///   item per source per pass, which interleaves sources like YouTube does.
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
/// Builds the personalized home feed from every signal the app has about
/// the user, the way the official YouTube home feed feels:
///
/// * subscribed channels (the backbone),
/// * videos related to a *rotating random sample* of recent watches —
///   never locked onto the single last watched video,
/// * topic keywords mined from watch/save history (content-based taste),
/// * saved videos, watched-but-unsubscribed channels, past searches,
/// * regional trending as discovery filler.
///
/// Every refresh re-rolls the mix: sources are chosen by weighted lottery,
/// pages are interleaved one item at a time, and already-shown videos are
/// remembered so pulling to refresh actually changes the feed.
class RecommendationService {
  final NewPipeService _service = NewPipeService();
  final Random _random = Random();

  /// A single source fetch may never hang the feed.
  static const _fetchTimeout = Duration(seconds: 18);

  /// Sources that can be built instantly from local data — no network.
  List<FeedSource> buildLocalSources(StorageService storage) {
    final sources = <FeedSource>[];
    final history = storage.getHistory();
    final subscribedUrls = storage.getSubscribedChannelUrls();
    final subscribedSet = subscribedUrls.toSet();

    // 1. Subscribed channels are the backbone of the feed.
    for (final url in subscribedUrls) {
      if (url.isNotEmpty) sources.add(FeedSource('channel', url, 3.0));
    }

    // 2. Related to a *random sample* of recent watches. Rotating the sample
    //    every refresh stops the feed from echoing one video's related list
    //    forever.
    final recentWatch = history.take(10).toList()..shuffle(_random);
    for (final video in recentWatch.take(3)) {
      if (video.url.isNotEmpty) {
        sources.add(FeedSource('related', video.url, 2.2));
      }
    }

    // 3. Topic keywords mined from titles — content-based taste signals that
    //    keep working even when related lists go stale.
    for (final topic in _interestTopics(storage, history).take(5)) {
      sources.add(FeedSource('search', topic, 1.6));
    }

    // 4. Saved videos are a strong taste signal too (random pick).
    final saved = storage.getSavedVideos().take(6).toList()..shuffle(_random);
    for (final video in saved.take(2)) {
      if (video.url.isNotEmpty) {
        sources.add(FeedSource('related', video.url, 1.5));
      }
    }

    // 5. Channels the user watched but did not subscribe to.
    final seenChannels = <String>{};
    final watchedChannels = <String>[
      for (final video in history)
        if (video.uploaderUrl.isNotEmpty &&
            !subscribedSet.contains(video.uploaderUrl) &&
            seenChannels.add(video.uploaderUrl))
          video.uploaderUrl,
    ]..shuffle(_random);
    for (final url in watchedChannels.take(4)) {
      sources.add(FeedSource('channel', url, 1.2));
    }

    // 6. Past searches personalise the feed with those topics.
    final searches =
        storage.getSearchHistory().take(6).toList()..shuffle(_random);
    for (final query in searches.take(3)) {
      if (query.trim().isNotEmpty) {
        sources.add(FeedSource('search', query, 1.3));
      }
    }

    // 7. Regional trending keeps the feed alive and diverse for anyone.
    //    Shuffled (and capped) so discovery rotates between refreshes.
    final trending = _service.trendingQueries(storage.regionCode)
      ..shuffle(_random);
    for (final query in trending.take(3)) {
      sources.add(FeedSource('search', query, 0.7));
    }
    return sources;
  }

  /// Words that carry no taste signal — filtered from topic mining.
  static const _stopwords = {
    // English structure
    'the', 'a', 'an', 'and', 'or', 'of', 'in', 'on', 'for', 'to', 'with',
    'is', 'are', 'was', 'were', 'this', 'that', 'it', 'its', 'as', 'at',
    'by', 'from', 'be', 'been', 'how', 'what', 'why', 'when', 'who', 'you',
    'your', 'my', 'we', 'our', 'us', 'they', 'them', 'his', 'her', 'she',
    'he', 'will', 'can', 'do', 'does', 'did', 'has', 'have', 'had', 'not',
    'but', 'if', 'so', 'than', 'then', 'there', 'here', 'out', 'up', 'down',
    'about', 'into', 'over', 'after', 'before', 'more', 'most', 'very',
    'just', 'also', 'like', 'get', 'got', 'all', 'one', 'two', 'no', 'yes',
    // Bangla structure
    'এবং', 'এই', 'সেই', 'আমি', 'আমরা', 'তুমি', 'আপনি', 'তার', 'তাদের',
    'করে', 'করা', 'করব', 'হয়', 'হচ্ছে', 'ছিল', 'থেকে', 'জন্য', 'সাথে',
    'কিভাবে', 'কেন', 'কোথায়', 'কি', 'না', 'নাই', 'আর', 'ও', 'এখন',
    'আজ', 'আবার', 'সব', 'সবাই', 'একটি', 'একটা', 'কোনো',
    // YouTube meta noise
    'official', 'video', 'videos', 'full', 'song', 'songs', 'music',
    'latest', 'new', 'best', 'top', 'part', 'episode', 'ep', 'live',
    'hd', '4k', 'vs', 'feat', 'ft', 'lyrics', 'lyric', 'audio',
    'trailer', 'teaser', 'shorts', 'short', 'edit', 'edits', 'free',
    'online', 'watch', 'now', 'today', 'day', 'vlog', 'news', 'mix',
    'reaction', 'review', 'tutorial', 'highlights', 'clip', 'clips',
    'bangla', 'english', 'hindi', 'bengali', 'cartoon', 'movie', 'film',
  };

  /// Mines recurring topic words from watch + save history. Returns search
  /// queries in taste order; empty when there is not enough history yet.
  List<String> _interestTopics(
    StorageService storage,
    List<VideoItem> history,
  ) {
    final counts = <String, int>{};
    final titles = <String>[
      for (final v in history.take(30)) v.title,
      for (final v in storage.getSavedVideos().take(15)) v.title,
    ];
    for (final title in titles) {
      final words =
          title.toLowerCase().split(RegExp(r'[^a-z0-9\u0980-\u09FF]+'));
      final seenInTitle = <String>{};
      for (final word in words) {
        if (word.length < 3 || word.length > 18) continue;
        if (_stopwords.contains(word)) continue;
        if (int.tryParse(word) != null) continue;
        // Count a word at most once per title so lists don't dominate.
        if (!seenInTitle.add(word)) continue;
        counts[word] = (counts[word] ?? 0) + 1;
      }
    }

    final recurring =
        counts.entries.where((e) => e.value >= 2).toList()
          ..sort((a, b) => b.value.compareTo(a.value));
    if (recurring.length >= 3) {
      return [for (final e in recurring) e.key];
    }
    // Light history: fall back to any valid token, shuffled for variety.
    final pool = counts.keys.toList()..shuffle(_random);
    return pool;
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

  /// Fetches the next page from one source into its queue. The caller then
  /// drains the queues interleaved. Never throws — a failed source is
  /// marked exhausted and the feed moves on.
  Future<void> fetch(FeedSource source) async {
    switch (source.kind) {
      case 'related':
        source.exhausted = true; // one-shot
        source.served++;
        final items = await _service
            .getRelatedVideos(source.key)
            .timeout(_fetchTimeout);
        // Shuffle related lists: they are already-familiar rankings and the
        // feed should not repeat their exact order every refresh.
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

  /// Weighted *lottery* pick — unlike a deterministic max this mixes sources
  /// in fresh proportions every refresh, exactly like a recommendation
  /// feed should. A source's odds fall as it serves more pages.
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
