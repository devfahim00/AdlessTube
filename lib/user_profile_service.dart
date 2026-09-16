import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'models.dart';
import 'storage_service.dart';
import 'topic_miner.dart';

/// ═══════════════════════ USER PROFILE ═══════════════════════
///
/// The on-device recommendation profile — everything the home feed knows
/// about the user, built from raw signals and never leaving the phone:
///
/// * **watch events** — how much of every video was actually watched
///   (watch percentage, not just "opened"), recorded by the playback
///   service every few seconds,
/// * **explicit signals** — "Not interested" and "Don't recommend
///   channel" taps from the feed menu,
/// * **subscriptions, liked songs, saved videos and searches** — pulled
///   from the existing storage boxes.
///
/// From those raw signals [rebuildProfile] derives two decaying taste
/// models:
///
/// * **channel affinity** — a score per channel: Σ watch% × decay, with a
///   completion bonus, a subscription bonus and penalties from
///   not-interested taps,
/// * **topic weights** — a weight per recurring keyword in the titles the
///   user actually watched (negative when the user rejected the topic).
///
/// Both models use a 7-day half-life, so last week's taste matters half
/// as much as today's — the feed slowly forgets and follows the user.
///
/// Everything lives in Hive boxes that are included in the backup
/// export/import, so a restored phone continues with the same profile
/// instead of starting cold.
class UserProfileService extends ChangeNotifier {
  /// Box with raw watch events (one entry per watch session).
  static const watchEventsBox = 'watch_events';

  /// Box with explicit feedback signals (not interested / blocked).
  static const signalsBox = 'user_signals';

  /// Derived per-channel affinity scores.
  static const channelAffinityBox = 'channel_affinity';

  /// Derived per-keyword topic weights.
  static const topicProfileBox = 'topic_profile';

  /// Interest half-life in days: a watch from 7 days ago carries half
  /// the weight of one from today.
  static const halfLifeDays = 7.0;

  final StorageService _storage;
  final Random _random = Random();

  UserProfileService(this._storage);

  // ─────────── Cached profile (rebuilt by rebuildProfile) ───────────
  Map<String, double> _channelScores = {};
  Map<String, double> _topicWeights = {};
  Set<String> _subscribedUrls = {};
  Set<String> _hiddenVideoIds = {};
  Set<String> _blockedChannels = {};
  bool _profileReady = false;

  bool get profileReady => _profileReady;

  /// Number of raw watch sessions recorded so far.
  int get watchEventCount => Hive.box(watchEventsBox).length;

  // ─────────── Init ───────────

  /// Opens the profile boxes and builds the taste models in the
  /// background. Safe to call on every start — watch events are raw
  /// facts, so rebuilding is idempotent.
  Future<void> init() async {
    await Hive.openBox(watchEventsBox);
    await Hive.openBox(signalsBox);
    await Hive.openBox(channelAffinityBox);
    await Hive.openBox(topicProfileBox);
    await rebuildProfile();
  }

  // ─────────── Watch session tracking (called by the player) ───────────

  String? _sessionKey;
  VideoItem? _sessionVideo;
  DateTime? _sessionStart;
  Duration _sessionMaxPosition = Duration.zero;
  Duration _sessionDuration = Duration.zero;

  /// Starts a new watch session for [video]. Any session still running
  /// is flushed first so switching videos never loses the previous one.
  ///
  /// [endWatchSession] captures and clears the old fields synchronously
  /// before its first await, so the fire-and-forget flush can never race
  /// with the new session that starts right after.
  void beginWatchSession(VideoItem video) {
    if (_sessionKey != null) {
      unawaited(endWatchSession());
    }
    _sessionKey = '${video.id}|${DateTime.now().millisecondsSinceEpoch}';
    _sessionVideo = video;
    _sessionStart = DateTime.now();
    _sessionMaxPosition = Duration.zero;
    _sessionDuration = Duration.zero;
  }

  /// Keeps the running session's high-water mark. Cheap — called on
  /// every position tick by the playback service.
  void updateWatchSession(Duration position, Duration duration) {
    if (position > _sessionMaxPosition) _sessionMaxPosition = position;
    if (duration > _sessionDuration) _sessionDuration = duration;
  }

  /// Writes the running session to the watch-events box without closing
  /// it (periodic checkpoint while the video keeps playing).
  Future<void> checkpointWatchSession() async {
    final key = _sessionKey;
    final video = _sessionVideo;
    final start = _sessionStart;
    if (key == null || video == null || start == null) return;
    await _writeSessionEvent(
      key,
      video,
      start,
      _sessionMaxPosition,
      _sessionDuration,
    );
  }

  /// Checkpoints and closes the running session (video closed or
  /// switched away). The session fields are captured and cleared
  /// synchronously, so calling this fire-and-forget from
  /// [beginWatchSession] is race-free.
  Future<void> endWatchSession() async {
    final key = _sessionKey;
    final video = _sessionVideo;
    final start = _sessionStart;
    final maxPosition = _sessionMaxPosition;
    final videoDuration = _sessionDuration;
    _sessionKey = null;
    _sessionVideo = null;
    _sessionStart = null;
    _sessionMaxPosition = Duration.zero;
    _sessionDuration = Duration.zero;
    if (key == null || video == null || start == null) return;
    await _writeSessionEvent(key, video, start, maxPosition, videoDuration);
  }

  Future<void> _writeSessionEvent(
    String key,
    VideoItem video,
    DateTime start,
    Duration maxPosition,
    Duration videoDuration,
  ) async {
    final durationSec = videoDuration.inSeconds;
    final watchedSec = maxPosition.inSeconds;
    // Ignore sessions that never really started (previews, instant
    // backs, lives without a known duration).
    if (durationSec < 5 || watchedSec < 3) return;
    final box = Hive.box(watchEventsBox);
    // Keep the earliest start for the session, update progress freely.
    final existing = box.get(key);
    final at = existing is Map
        ? ((existing['at'] as num?)?.toInt() ?? start.millisecondsSinceEpoch)
        : start.millisecondsSinceEpoch;
    await box.put(key, {
      'videoId': video.id,
      'channelUrl': video.uploaderUrl,
      'channelName': video.uploader,
      'title': video.title,
      'durationSec': durationSec,
      'watchedSec': watchedSec,
      'at': at,
    });
  }

  // ─────────── Explicit feedback (feed tile menu) ───────────

  /// "Not interested": hides this video forever and pushes its title
  /// topics (and channel, softly) towards negative weights.
  Future<void> markNotInterested(VideoItem video) async {
    await Hive.box(signalsBox).put('ni:${video.id}', {
      'type': 'not_interested',
      'videoId': video.id,
      'channelUrl': video.uploaderUrl,
      'channelName': video.uploader,
      'title': video.title,
      'at': DateTime.now().millisecondsSinceEpoch,
    });
    _hiddenVideoIds.add(video.id);
    // Apply the negative topic weights immediately (no full rebuild
    // needed for the feed to react on the next refresh).
    final now = DateTime.now().millisecondsSinceEpoch;
    final decay = _decay(now);
    final topicBox = Hive.box(topicProfileBox);
    for (final token in TopicMiner.tokenize(video.title).toSet()) {
      final raw = topicBox.get(token);
      final weight = (raw is Map ? (raw['weight'] as num?)?.toDouble() : null) ?? 0.0;
      final hits = (raw is Map ? (raw['hits'] as int?) : null) ?? 0;
      final newWeight = weight - 0.9 * decay;
      _topicWeights[token] = newWeight;
      await topicBox.put(token, {
        'weight': newWeight,
        'hits': hits,
        'lastSeen': now,
      });
    }
    if (video.uploaderUrl.isNotEmpty) {
      _channelScores[video.uploaderUrl] =
          (_channelScores[video.uploaderUrl] ?? 0) - 0.6 * decay;
    }
    notifyListeners();
  }

  /// "Don't recommend channel": hard-filters every video of the channel
  /// from the feed.
  Future<void> blockChannel(String channelUrl, String channelName) async {
    if (channelUrl.isEmpty) return;
    await Hive.box(signalsBox).put('block:$channelUrl', {
      'type': 'block_channel',
      'channelUrl': channelUrl,
      'channelName': channelName,
      'at': DateTime.now().millisecondsSinceEpoch,
    });
    _blockedChannels.add(channelUrl);
    notifyListeners();
  }

  /// Restores a hidden video (undo).
  Future<void> undoNotInterested(String videoId) async {
    await Hive.box(signalsBox).delete('ni:$videoId');
    _hiddenVideoIds.remove(videoId);
    await rebuildProfile();
  }

  /// Lifts a channel block (undo).
  Future<void> unblockChannel(String channelUrl) async {
    await Hive.box(signalsBox).delete('block:$channelUrl');
    _blockedChannels.remove(channelUrl);
    notifyListeners();
  }

  bool isVideoHidden(String videoId) => _hiddenVideoIds.contains(videoId);

  bool isChannelBlocked(String channelUrl) => _blockedChannels.contains(channelUrl);

  /// Human names of blocked channels (for a settings list).
  Map<String, String> get blockedChannelNames {
    final box = Hive.box(signalsBox);
    final names = <String, String>{};
    for (final key in box.keys) {
      if (key.toString().startsWith('block:')) {
        final value = box.get(key);
        if (value is Map) {
          names[key.toString().substring(6)] = (value['channelName'] ?? '').toString();
        }
      }
    }
    return names;
  }

  // ─────────── Profile rebuild ───────────

  /// Rebuilds the channel-affinity and topic models from every raw
  /// signal on the device. Runs on app start, after every import and
  /// whenever the feed is pulled to refresh — a few thousand events
  /// aggregate in milliseconds, so it is safe on the main isolate.
  Future<void> rebuildProfile() async {
    final eventsBox = Hive.box(watchEventsBox);
    final signalBox = Hive.box(signalsBox);

    final channelScores = <String, double>{};
    final channelNames = <String, String>{};
    final topicWeights = <String, double>{};
    final lastWatchAt = <String, int>{};

    // ── 1. Backfill: history entries from before this update never got
    //      watch events. Synthesize weak ones (30% watched, aged 3
    //      half-lives) once — from then on they are ordinary events.
    final hasEvent = <String>{};
    for (final value in eventsBox.values) {
      if (value is! Map) continue;
      final id = value['videoId']?.toString() ?? '';
      if (id.isNotEmpty) hasEvent.add(id);
    }
    final backfillAt =
        DateTime.now().millisecondsSinceEpoch - 21 * 24 * 3600 * 1000;
    for (final video in _storage.getHistory()) {
      if (hasEvent.contains(video.id)) continue;
      final duration = video.duration?.inSeconds ?? 0;
      await eventsBox.put('backfill|${video.id}', {
        'videoId': video.id,
        'channelUrl': video.uploaderUrl,
        'channelName': video.uploader,
        'title': video.title,
        'durationSec': duration > 0 ? duration : 600,
        'watchedSec': duration > 0 ? (duration * 0.3).round() : 180,
        'at': backfillAt,
      });
    }

    // ── 2. Watch events: the strongest signal.
    for (final value in eventsBox.values) {
      if (value is! Map) continue;
      final channelUrl = value['channelUrl']?.toString() ?? '';
      final channelName = value['channelName']?.toString() ?? '';
      final title = value['title']?.toString() ?? '';
      final durationSec = (value['durationSec'] as num?)?.toInt() ?? 0;
      final watchedSec = (value['watchedSec'] as num?)?.toInt() ?? 0;
      final at = (value['at'] as num?)?.toInt() ?? 0;
      if (channelUrl.isNotEmpty && channelName.isNotEmpty) {
        channelNames[channelUrl] = channelName;
      }
      if (at > (lastWatchAt[channelUrl] ?? 0)) lastWatchAt[channelUrl] = at;
      if (durationSec < 5) continue;

      final watchPct = (watchedSec / durationSec).clamp(0.0, 1.0).toDouble();
      final decay = _decay(at);
      // Watching most of a video is a much stronger vote than opening
      // it, and finishing gets a bonus.
      final strength = watchPct < 0.1
          ? -0.15 // instant skip: a mild negative
          : watchPct * 2.0 + (watchPct >= 0.85 ? 0.5 : 0.0);
      final vote = strength * decay;
      if (channelUrl.isNotEmpty) {
        channelScores[channelUrl] =
            (channelScores[channelUrl] ?? 0.0) + vote;
      }
      // Topics: each title keyword gains a share of the vote, counted
      // once per title.
      if (title.isNotEmpty) {
        for (final token in TopicMiner.tokenize(title).toSet()) {
          topicWeights[token] = (topicWeights[token] ?? 0.0) + 0.45 * vote;
        }
      }
    }

    // ── 3. Subscriptions: a solid baseline for channel affinity.
    _subscribedUrls = _storage.getSubscribedChannelUrls().toSet();
    for (final entry in _storage.getSubscriptions().entries) {
      channelScores[entry.key] = (channelScores[entry.key] ?? 0.0) + 1.5;
      final name = entry.value['name']?.toString() ?? '';
      if (name.isNotEmpty) channelNames[entry.key] = name;
    }

    // ── 4. Liked songs: strong positive topic + channel signal.
    for (final song in _storage.getLikedSongs()) {
      if (song.uploaderUrl.isNotEmpty) {
        channelScores[song.uploaderUrl] =
            (channelScores[song.uploaderUrl] ?? 0.0) + 0.5;
        if (song.uploader.isNotEmpty) {
          channelNames[song.uploaderUrl] = song.uploader;
        }
      }
      for (final token in TopicMiner.tokenize(song.title).toSet()) {
        topicWeights[token] = (topicWeights[token] ?? 0.0) + 0.5;
      }
    }

    // ── 5. Saved videos: medium positive signal.
    for (final video in _storage.getSavedVideos()) {
      if (video.uploaderUrl.isNotEmpty) {
        channelScores[video.uploaderUrl] =
            (channelScores[video.uploaderUrl] ?? 0.0) + 0.4;
      }
      for (final token in TopicMiner.tokenize(video.title).toSet()) {
        topicWeights[token] = (topicWeights[token] ?? 0.0) + 0.4;
      }
    }

    // ── 6. Searches: active intent, small but fresh.
    for (final query in _storage.getSearchHistory()) {
      for (final token in TopicMiner.tokenize(query).toSet()) {
        topicWeights[token] = (topicWeights[token] ?? 0.0) + 0.3;
      }
    }

    // ── 7. Explicit rejections: not-interested pushes the video's
    //      topics (and channel, softly) negative — decaying, so one
    //      rejection does not haunt a topic forever.
    _hiddenVideoIds = {};
    _blockedChannels = {};
    for (final value in signalBox.values) {
      if (value is! Map) continue;
      final type = value['type']?.toString() ?? '';
      final at = (value['at'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch;
      final decay = _decay(at);
      if (type == 'not_interested') {
        final videoId = value['videoId']?.toString() ?? '';
        if (videoId.isNotEmpty) _hiddenVideoIds.add(videoId);
        final title = value['title']?.toString() ?? '';
        for (final token in TopicMiner.tokenize(title).toSet()) {
          topicWeights[token] = (topicWeights[token] ?? 0.0) - 0.9 * decay;
        }
        final channelUrl = value['channelUrl']?.toString() ?? '';
        if (channelUrl.isNotEmpty) {
          channelScores[channelUrl] =
              (channelScores[channelUrl] ?? 0.0) - 0.6 * decay;
        }
      } else if (type == 'block_channel') {
        final channelUrl = value['channelUrl']?.toString() ?? '';
        if (channelUrl.isNotEmpty) _blockedChannels.add(channelUrl);
      }
    }

    // ── 8. Persist the derived models (they travel inside backups too,
    //      and importing restores them even before a rebuild).
    final affinityBox = Hive.box(channelAffinityBox);
    await affinityBox.clear();
    for (final entry in channelScores.entries) {
      if (entry.value == 0) continue;
      await affinityBox.put(entry.key, {
        'name': channelNames[entry.key] ?? '',
        'score': entry.value,
        'lastWatch': lastWatchAt[entry.key] ?? 0,
      });
    }
    final topicBox = Hive.box(topicProfileBox);
    await topicBox.clear();
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final entry in topicWeights.entries) {
      if (entry.value.abs() < 0.05) continue;
      await topicBox.put(entry.key, {
        'weight': entry.value,
        'hits': 1,
        'lastSeen': now,
      });
    }

    _channelScores = channelScores;
    _topicWeights = topicWeights;
    _profileReady = true;
    notifyListeners();
  }

  // ─────────── Scoring (the ranking engine's core) ───────────

  /// Time-decay factor for a signal recorded at [atMillis]: 1.0 today,
  /// 0.5 a week ago, 0.25 two weeks ago…
  double _decay(int atMillis, [DateTime? now]) {
    final ageDays = (now ?? DateTime.now())
            .difference(DateTime.fromMillisecondsSinceEpoch(atMillis))
            .inMinutes /
        (60 * 24);
    if (ageDays <= 0) return 1.0;
    return pow(0.5, ageDays / halfLifeDays).toDouble();
  }

  /// Raw (unnormalized) affinity of a channel.
  double rawAffinityOf(String channelUrl) =>
      channelUrl.isEmpty ? 0.0 : (_channelScores[channelUrl] ?? 0.0);

  /// Channel affinity normalized to 0..1 with a saturating curve, so
  /// one binge does not max out a channel forever.
  double affinityOf(String channelUrl) {
    final raw = rawAffinityOf(channelUrl);
    if (raw <= 0) return 0.0;
    return raw / (raw + 2.5);
  }

  /// Topic match of a title against the taste model: positive when the
  /// title's keywords are liked topics, negative when rejected ones.
  double topicMatch(String title) {
    final tokens = TopicMiner.tokenize(title).toSet();
    if (tokens.isEmpty) return 0.0;
    var sum = 0.0;
    for (final token in tokens) {
      sum += _topicWeights[token] ?? 0.0;
    }
    return sum / (sum.abs() + 2.0);
  }

  double _popularity(int? viewCount) {
    if (viewCount == null || viewCount <= 0) return 0.0;
    return (log(1 + viewCount) / log(1 + 1000000))
        .clamp(0.0, 1.0)
        .toDouble();
  }

  /// Final 0..1-ish ranking score for a candidate video: channel
  /// affinity + topic match + popularity + a small exploration roll
  /// (keeps the feed from becoming a filter bubble), minus explicit
  /// penalties for rejected topics.
  double scoreVideo(VideoItem video) {
    final affinity = affinityOf(video.uploaderUrl);
    final topics = topicMatch(video.title);
    final popularity = _popularity(video.viewCount);
    final explore = _random.nextDouble() * 0.10;
    var score = 0.42 * affinity +
        0.30 * (topics > 0 ? topics : 0.0) +
        0.10 * popularity +
        0.10 * explore;
    if (topics < 0) score += 0.35 * topics; // rejected-topic penalty
    if (_subscribedUrls.contains(video.uploaderUrl)) score += 0.06;
    return score;
  }

  // ─────────── Source builders (what the feed should fetch) ───────────

  /// Strongest positive topics, for search-based candidate sources.
  List<String> topTopics(int count) {
    final entries = _topicWeights.entries
        .where((e) => e.value >= 0.4)
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [for (final e in entries.take(count)) e.key];
  }

  /// Channels the user watches a lot but has not subscribed to.
  List<String> highAffinityChannels(int count) {
    final entries = _channelScores.entries
        .where((e) =>
            e.key.isNotEmpty &&
            e.value >= 1.2 &&
            !_subscribedUrls.contains(e.key) &&
            !_blockedChannels.contains(e.key))
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [for (final e in entries.take(count)) e.key];
  }

  /// Recent watches sorted by taste relevance (watch% × decay) — the
  /// best seeds for related-video sources. Returns watch URLs.
  List<String> bestRecentWatchUrls(int count) {
    final events = <_RankedEvent>[];
    for (final value in Hive.box(watchEventsBox).values) {
      if (value is! Map) continue;
      final videoId = value['videoId']?.toString() ?? '';
      final durationSec = (value['durationSec'] as num?)?.toInt() ?? 0;
      final watchedSec = (value['watchedSec'] as num?)?.toInt() ?? 0;
      final at = (value['at'] as num?)?.toInt() ?? 0;
      if (videoId.isEmpty || durationSec < 5) continue;
      final watchPct =
          (watchedSec / durationSec).clamp(0.0, 1.0).toDouble();
      // Only videos the user genuinely engaged with seed related fetches.
      if (watchPct < 0.25) continue;
      events.add(_RankedEvent(
        url: 'https://www.youtube.com/watch?v=$videoId',
        rank: watchPct * _decay(at),
      ));
    }
    events.sort((a, b) => b.rank.compareTo(a.rank));
    // De-duplicate by url while keeping order.
    final seen = <String>{};
    final urls = <String>[];
    for (final e in events) {
      if (seen.add(e.url)) urls.add(e.url);
      if (urls.length >= count) break;
    }
    return urls;
  }

  /// Lightweight summary for a settings/debug row.
  Map<String, dynamic> get profileSummary => {
        'watchEvents': Hive.box(watchEventsBox).length,
        'channels': _channelScores.length,
        'topics': _topicWeights.length,
        'blockedChannels': _blockedChannels.length,
        'hiddenVideos': _hiddenVideoIds.length,
      };
}

class _RankedEvent {
  final String url;
  final double rank;
  const _RankedEvent({required this.url, required this.rank});
}
