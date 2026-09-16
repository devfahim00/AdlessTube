import 'dart:math';

import 'models.dart';

/// ═══════════════════════ TOPIC MINER ═══════════════════════
///
/// Shared taste-signal mining used by both the home feed and the Shorts
/// feed: it turns a list of watched/saved videos into recurring topic
/// keywords, so both surfaces can recommend "more like what you watch"
/// without duplicating logic (and without either service importing the
/// other).
class TopicMiner {
  /// Words that carry no taste signal — filtered from topic mining.
  static const stopwords = {
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

  /// Tokenizes [title] into taste-signal keywords: lowercased, split on
  /// non-letters, stopwords / numbers / too-short fragments removed.
  /// Public so the user-profile engine can score any candidate title
  /// with exactly the same rules used to mine interests.
  static List<String> tokenize(String title) {
    if (title.isEmpty) return const [];
    final words =
        title.toLowerCase().split(RegExp(r'[^a-z0-9\u0980-\u09FF]+'));
    final tokens = <String>[];
    for (final word in words) {
      if (word.length < 3 || word.length > 18) continue;
      if (stopwords.contains(word)) continue;
      if (int.tryParse(word) != null) continue;
      tokens.add(word);
    }
    return tokens;
  }

  /// Recurring topic keywords from [videos], strongest first.
  ///
  /// A word is only counted once per title so playlists from one channel
  /// cannot dominate, and single occurrences are dropped when there is
  /// enough history to find genuinely recurring interests.
  static List<String> mineTopics(List<VideoItem> videos, {Random? random}) {
    final counts = <String, int>{};
    for (final video in videos) {
      if (video.title.isEmpty) continue;
      // One occurrence per title: tokenize, then deduplicate.
      for (final word in tokenize(video.title).toSet()) {
        counts[word] = (counts[word] ?? 0) + 1;
      }
    }

    final recurring = counts.entries.where((e) => e.value >= 2).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (recurring.length >= 3) {
      return [for (final e in recurring) e.key];
    }
    // Light history: fall back to any valid token, shuffled for variety.
    final pool = counts.keys.toList()..shuffle(random ?? Random());
    return pool;
  }
}
