import 'package:newpipeextractor_dart/newpipeextractor_dart.dart';
import 'models.dart';
import 'topic_miner.dart';

class NewPipeService {
  /// Channel profiles cached per URL so avatars are fetched only once.
  final Map<String, ChannelProfile> _channelProfileCache = {};

  // ═══════════════════ STREAM CACHE (shared) ═══════════════════
  //
  // NewPipeService is instantiated in many places (screens, playback and
  // download services), so the resolved-streams cache is static and shared
  // by every instance. One extraction now serves:
  //   * the player (video + audio-track pick),
  //   * the audio-language menu (same fetch),
  //   * the download flow,
  //   * Shorts preloading the next video ahead of the swipe.
  // Stream URLs stay valid for hours, so a short TTL is plenty.
  static const _streamCacheTtl = Duration(minutes: 15);
  static const _streamCacheMaxEntries = 24;
  static final Map<String, YoutubeVideo> _streamCache = {};
  static final Map<String, DateTime> _streamCacheTimes = {};

  Future<YoutubeVideo> _getVideo(String videoUrl) async {
    final cached = _streamCache[videoUrl];
    final cachedAt = _streamCacheTimes[videoUrl];
    if (cached != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < _streamCacheTtl) {
      return cached;
    }
    final video = await VideoExtractor.getStream(videoUrl);
    if (_streamCache.length >= _streamCacheMaxEntries &&
        !_streamCache.containsKey(videoUrl)) {
      final oldest = _streamCacheTimes.keys.toList()
        ..sort((a, b) =>
            _streamCacheTimes[a]!.compareTo(_streamCacheTimes[b]!));
      final excess = _streamCache.length - _streamCacheMaxEntries + 1;
      for (final key in oldest.take(excess)) {
        _streamCache.remove(key);
        _streamCacheTimes.remove(key);
      }
    }
    _streamCache[videoUrl] = video;
    _streamCacheTimes[videoUrl] = DateTime.now();
    return video;
  }

  /// Resolves streams for [videoUrl] ahead of time (Shorts preload).
  /// Errors are swallowed — warming is best-effort only.
  Future<void> warmStreamCache(String videoUrl) async {
    try {
      await _getVideo(videoUrl);
    } catch (_) {}
  }

  // ═══════════════════ SEARCH ═══════════════════

  Future<List<VideoItem>> searchVideos(String query) async {
    final response = await SearchExtractor.searchYoutube(
      query,
      [SearchFilter.videos.value],
    );
    final videos = response.result.videos;
    return videos.map(_toVideo).where(_isPlayable).toList();
  }

  Future<List<ChannelItem>> searchChannels(String query) async {
    final response = await SearchExtractor.searchYoutube(
      query,
      [SearchFilter.channels.value],
    );
    final channels = response.result.channels;
    return channels.map(_toChannel).toList();
  }

  Future<({List<VideoItem> items, PageToken? next})> searchVideoPage(
    String query, {
    PageToken? next,
  }) async {
    final page = next == null
        ? await SearchExtractor.searchYoutube(
            query, [SearchFilter.videos.value])
        : await SearchExtractor.searchNextPage(
            query, [SearchFilter.videos.value], next);
    return (
      items: page.result.videos.map(_toVideo).where(_isPlayable).toList(),
      next: page.next,
    );
  }

  Future<({List<ChannelItem> items, PageToken? next})> searchChannelPage(
    String query, {
    PageToken? next,
  }) async {
    final page = next == null
        ? await SearchExtractor.searchYoutube(
            query, [SearchFilter.channels.value])
        : await SearchExtractor.searchNextPage(
            query, [SearchFilter.channels.value], next);
    return (
      items: page.result.channels.map(_toChannel).toList(),
      next: page.next,
    );
  }

  // ═══════════════════ TRENDING ═══════════════════

  /// Search queries that back the home feed. The home screen pages through
  /// these round-robin so the feed can grow endlessly while scrolling.
  List<String> trendingQueries(String region) {
    final regionName = _regionToName(region);
    return [
      '$regionName trending',
      '$regionName popular videos',
      '$regionName news',
      '$regionName music videos',
      '$regionName viral videos',
    ];
  }

  /// Search queries that back the music feed, seeded from liked songs.
  List<String> musicQueries({
    required String region,
    List<VideoItem> likedSongs = const [],
  }) {
    final regionName = _regionToName(region);
    return [
      ...likedSongs
          .where((song) => song.title.trim().isNotEmpty)
          .take(3)
          .map((song) => '${song.title} music'),
      '$regionName popular music',
      '$regionName new songs',
      '$regionName top songs',
    ];
  }

  Future<List<VideoItem>> getTrending({String region = 'US'}) async {
    final regionName = _regionToName(region);
    final queries = [
      '$regionName trending',
      '$regionName popular',
      '$regionName news',
      '$regionName music',
    ];

    final Set<String> seen = {};
    final List<VideoItem> all = [];

    for (final q in queries) {
      try {
        final res = await SearchExtractor.searchYoutube(
          q,
          [SearchFilter.videos.value],
        );
        for (final v in res.result.videos) {
          final item = _toVideo(v);
          if (_isPlayable(item) && !seen.contains(item.id)) {
            seen.add(item.id);
            all.add(item);
          }
          if (all.length >= 40) break;
        }
      } catch (_) {}
      if (all.length >= 40) break;
    }
    return all;
  }

  // ═══════════════════ CHANNEL ═══════════════════

  /// Channel uploads — শুধু একটাই reliable method আছে।
  Future<List<VideoItem>> getChannelVideos(String channelUrl) async {
    try {
      final result = await ChannelExtractor.getChannelUploads(channelUrl);
      return result.items.map(_toVideo).where(_isPlayable).toList();
    } catch (_) {
      return [];
    }
  }

  /// Lightweight channel profile (avatar + subscriber count) used by the
  /// player and channel screens. Results are cached per channel URL.
  Future<ChannelProfile> getChannelProfile(String channelUrl) async {
    if (channelUrl.isEmpty) {
      return const ChannelProfile(name: '', avatarUrl: '');
    }
    final cached = _channelProfileCache[channelUrl];
    if (cached != null) return cached;
    try {
      final info = await ChannelExtractor.getChannelInfo(channelUrl);
      final profile = ChannelProfile(
        name: info.name ?? '',
        avatarUrl: _firstNonEmpty(info.avatars),
        subscriberCount: info.subscriberCount,
      );
      _channelProfileCache[channelUrl] = profile;
      return profile;
    } catch (_) {
      return const ChannelProfile(name: '', avatarUrl: '');
    }
  }

  /// A channel shorts-tab fetch that never throws — failures just give
  /// an empty page so one dead channel cannot break the Shorts feed.
  Future<({List<VideoItem> items, PageToken? next})> _safeShortsTab(
      String channelUrl) async {
    try {
      return await getChannelTabPage(channelUrl, 'shorts');
    } catch (_) {
      return (items: <VideoItem>[], next: null);
    }
  }

  /// A video-search page fetch that never throws.
  Future<({List<VideoItem> items, PageToken? next})> _safeSearchPage(
      String query) async {
    try {
      return await searchVideoPage(query);
    } catch (_) {
      return (items: <VideoItem>[], next: null);
    }
  }

  /// ═══════════════════ SHORTS FEED ═══════════════════
  ///
  /// Personalized Shorts, built the way the official app feels:
  /// * shorts from subscribed channels,
  /// * shorts from channels the user watches a lot (but didn't subscribe),
  /// * shorts about the topics the user usually watches (taste mining),
  /// * always a slice of random/regional shorts for discovery.
  ///
  /// Every source is capped and the final list is interleaved one short
  /// per source per pass, so the same channel never dominates the feed —
  /// and random shorts keep appearing between the personalized ones.
  Future<List<VideoItem>> getShorts({
    required String region,
    List<String> subscribedChannels = const [],
    List<VideoItem> watchHistory = const [],
  }) async {
    final seen = <String>{};
    // channel key -> capped list of shorts
    final buckets = <String, List<VideoItem>>{};

    bool isShortLike(VideoItem v) =>
        v.isShort ||
        (v.duration != null &&
            v.duration!.inSeconds > 0 &&
            v.duration!.inSeconds <= 180);

    void addAll(Iterable<VideoItem> items, String bucketKey, {int cap = 3}) {
      for (final item in items) {
        if (item.isLive || !isShortLike(item)) continue;
        if (!seen.add(item.id)) continue;
        final list = buckets.putIfAbsent(bucketKey, () => []);
        if (list.length < cap) list.add(item);
      }
    }

    // Channels worth pulling shorts from: subscriptions first, then the
    // channels that show up most often in recent watch history.
    final subscribed = subscribedChannels.toList()..shuffle();
    final historyChannels = <String, int>{};
    for (final video in watchHistory.take(40)) {
      final url = video.uploaderUrl;
      if (url.isEmpty || subscribed.contains(url)) continue;
      historyChannels[url] = (historyChannels[url] ?? 0) + 1;
    }
    final frequentHistoryChannels = historyChannels.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final channelUrls = [
      ...subscribed.take(4),
      ...frequentHistoryChannels.take(4).map((e) => e.key),
    ];

    // Pull every channel's shorts tab in parallel; a channel that fails
    // simply contributes nothing instead of breaking the whole feed.
    final channelResults = await Future.wait(
      [for (final url in channelUrls) _safeShortsTab(url)],
    );
    for (var i = 0; i < channelUrls.length && i < channelResults.length; i++) {
      addAll(channelResults[i].items, channelUrls[i]);
    }

    // Topic-based shorts: what the user usually watches, as shorts.
    final topics = TopicMiner.mineTopics(watchHistory.take(30).toList())
        .take(4)
        .toList();
    final regionName = _regionToName(region);
    final randomQueries = [
      '$regionName shorts',
      'popular shorts $regionName',
      'viral shorts',
    ]..shuffle();

    final searchQueries = [
      for (final topic in topics) '$topic shorts',
      ...randomQueries.take(2),
    ];
    final searchResults = await Future.wait(
      [for (final q in searchQueries) _safeSearchPage(q)],
    );
    final randomPool = <VideoItem>[];
    for (var i = 0; i < searchQueries.length; i++) {
      // Topic results go to their own bucket (still channel-capped later
      // by interleave); random/regional ones mix into one discovery pool.
      if (i < topics.length) {
        addAll(searchResults[i].items, 'topic-${searchQueries[i]}');
      } else {
        randomPool.addAll(searchResults[i].items);
      }
    }
    randomPool.shuffle();
    addAll(randomPool, 'random', cap: 6);

    // Interleave: one short per bucket per pass → no two consecutive
    // shorts from the same channel, random ones woven in between.
    final queues = buckets.values.toList()..shuffle();
    final feed = <VideoItem>[];
    var remaining = queues.any((q) => q.isNotEmpty);
    while (remaining) {
      remaining = false;
      for (final queue in queues) {
        if (queue.isNotEmpty) {
          feed.add(queue.removeAt(0));
          if (queue.isNotEmpty) remaining = true;
        }
      }
    }
    return feed;
  }

  /// Builds a music discovery feed from the user's liked songs and region.
  /// NewPipe does not expose account recommendations, so likes are the local
  /// preference signal used to find related artists, tracks and mixes.
  Future<List<VideoItem>> getMusicFeed({
    required String region,
    List<VideoItem> likedSongs = const [],
  }) async {
    final regionName = _regionToName(region);
    final queries = <String>[
      ...likedSongs
          .where((song) => song.title.trim().isNotEmpty)
          .take(3)
          .map((song) => '${song.title} music'),
      '$regionName popular music',
      '$regionName new songs',
    ];
    final seen = <String>{};
    final music = <VideoItem>[];

    for (final query in queries) {
      try {
        final page = await searchVideoPage(query);
        for (final item in page.items) {
          if (!item.isLive && !item.isShort && seen.add(item.id)) {
            music.add(item);
          }
        }
      } catch (_) {}
    }
    music.shuffle();
    return music;
  }

  Future<({List<VideoItem> items, PageToken? next})> getChannelTabPage(
    String channelUrl,
    String tab, {
    PageToken? next,
  }) async {
    if (tab == 'videos') {
      try {
        final page = next == null
            ? await ChannelExtractor.getChannelTabContent(channelUrl, tab)
            : await ChannelExtractor.getChannelTabNextPage(
                channelUrl, tab, next);
        return (
          items: page.streams.map(_toVideo).where(_isPlayable).toList(),
          next: page.next,
        );
      } catch (_) {
        final page = next == null
            ? await ChannelExtractor.getChannelUploads(channelUrl)
            : await ChannelExtractor.getChannelNextPage(channelUrl, next);
        return (
          items: page.items.map(_toVideo).where(_isPlayable).toList(),
          next: page.next,
        );
      }
    }
    try {
      final page = next == null
          ? await ChannelExtractor.getChannelTabContent(channelUrl, tab)
          : await ChannelExtractor.getChannelTabNextPage(channelUrl, tab, next);
      return (
        items: page.streams.map(_toVideo).where(_isPlayable).toList(),
        next: page.next,
      );
    } catch (_) {
      // Many channels do not have a Shorts tab. Treat it as an empty list.
      return (items: <VideoItem>[], next: null);
    }
  }

  // ═══════════════════ RELATED ═══════════════════

  // Related lists are shared across service instances (player page, mini
  // player re-entry, feed warm-up) — a static cache makes going back into
  // a video page instant instead of re-fetching everything.
  static const _relatedCacheTtl = Duration(minutes: 30);
  static const _relatedCacheMaxEntries = 12;
  static final Map<String, List<VideoItem>> _relatedCache = {};
  static final Map<String, DateTime> _relatedCacheTimes = {};

  /// Videos related to [videoUrl]. Served from cache when fresh; the network
  /// call has a hard timeout so a hanging extractor can never freeze the
  /// player page spinner. [forceRefresh] bypasses the cache read.
  Future<List<VideoItem>> getRelatedVideos(
    String videoUrl, {
    bool forceRefresh = false,
  }) async {
    final cached = _relatedCache[videoUrl];
    final cachedAt = _relatedCacheTimes[videoUrl];
    if (!forceRefresh &&
        cached != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < _relatedCacheTtl) {
      return cached;
    }
    try {
      final response = await ServiceExtractor.getRelatedItems(0, videoUrl)
          .timeout(const Duration(seconds: 15));
      final videos = response.videos.map(_toVideo).where(_isPlayable).toList();
      if (videos.isNotEmpty) {
        if (_relatedCache.length >= _relatedCacheMaxEntries &&
            !_relatedCache.containsKey(videoUrl)) {
          final oldest = _relatedCacheTimes.keys.toList()
            ..sort((a, b) =>
                _relatedCacheTimes[a]!.compareTo(_relatedCacheTimes[b]!));
          final excess =
              _relatedCache.length - _relatedCacheMaxEntries + 1;
          for (final key in oldest.take(excess)) {
            _relatedCache.remove(key);
            _relatedCacheTimes.remove(key);
          }
        }
        _relatedCache[videoUrl] = videos;
        _relatedCacheTimes[videoUrl] = DateTime.now();
      }
      return videos;
    } catch (_) {
      // Timeout/error — stale cache beats an empty list.
      return cached ?? const [];
    }
  }

  // ═══════════════════ STREAMS ═══════════════════

  /// Muxed streams return করি। Video-only merge টা YouTube এ
  /// muxed 360p এ cap থাকে — এটাই সবচেয়ে stable।
  /// Higher quality পেতে চাইলে ভবিষ্যতে youtube_explode_dart use করতে হবে।
  Future<List<VideoStreamInfo>> getAvailableStreams(String videoUrl) async {
    final video = await _getVideo(videoUrl);
    final Map<String, VideoStreamInfo> result = {};

    // YouTube exposes HD formats as video-only DASH streams. Pair each one
    // with matching audio so media_kit/mpv can play it with sound.
    try {
      for (final stream in video.videoOnlyStreams) {
        final videoOnlyUrl = stream.url;
        final audioUrl = _bestAudioFor(video,
            videoFormatSuffix: stream.formatSuffix)?.url;
        if (videoOnlyUrl == null ||
            videoOnlyUrl.isEmpty ||
            audioUrl == null ||
            audioUrl.isEmpty) {
          continue;
        }
        final quality = _normalizeQuality(stream.resolution);
        final format = (stream.formatSuffix ??
                stream.formatName ??
                'adaptive')
            .toLowerCase();
        result['$quality-$format'] = VideoStreamInfo(
          url: videoOnlyUrl,
          audioUrl: audioUrl,
          quality: quality,
          format: format,
          container: _containerOf(stream.formatSuffix, stream.formatName),
        );
      }
    } catch (_) {}

    // ── Muxed streams ──
    try {
      final muxedList = video.videoStreams;
      for (final s in muxedList) {
        final url = s.url;
        if (url == null || url.isEmpty) continue;
        final q = _normalizeQuality(s.resolution);
        result['$q-muxed'] = VideoStreamInfo(
          url: url,
          quality: q,
          format: 'muxed',
          container: _containerOf(s.formatSuffix, s.formatName),
        );
      }
    } catch (_) {}

    // ── Fallback: videoWithHighestQuality ──
    if (result.isEmpty) {
      try {
        final muxed = video.videoWithHighestQuality;
        if (muxed != null) {
          final muxedUrl = muxed.url;
          if (muxedUrl != null && muxedUrl.isNotEmpty) {
            final q = _normalizeQuality(muxed.resolution);
            result['$q-muxed'] = VideoStreamInfo(
              url: muxedUrl,
              quality: q,
              format: 'muxed',
              container: _containerOf(muxed.formatSuffix, muxed.formatName),
            );
          }
        }
      } catch (_) {}
    }

    final list = result.values.toList();
    list.sort((a, b) =>
        _qualityRank(b.quality).compareTo(_qualityRank(a.quality)));
    return list;
  }

  /// Returns the extractor's highest-quality audio-only stream for Music.
  /// Prefers the original language on multi-track (dubbed) videos.
  Future<VideoStreamInfo?> getBestAudioStream(String videoUrl) async {
    final video = await _getVideo(videoUrl);
    final audio =
        _bestAudioFor(video) ?? video.audioWithHighestQuality;
    final url = audio?.url;
    if (url == null || url.isEmpty) return null;
    final format = (audio?.formatSuffix ?? audio?.formatName ?? 'audio')
        .toLowerCase();
    return VideoStreamInfo(
      url: url,
      quality: 'Audio',
      format: format,
    );
  }

  /// Distinct selectable audio languages for a video (original + dubs).
  /// Videos with a single track return a one-element list.
  Future<List<AudioTrackOption>> getAudioTracks(String videoUrl) async {
    try {
      final video = await _getVideo(videoUrl);
      final groups = <String, List<AudioOnlyStream>>{};
      for (final stream in video.audioOnlyStreams) {
        final url = stream.url;
        if (url == null || url.isEmpty) continue;
        final locale = (stream.audioTrackLocale ?? '').trim();
        final rawName = (stream.audioTrackName ?? '').trim();
        final type =
            (stream.audioTrackType ?? '').trim().toUpperCase();
        groups
            .putIfAbsent('$locale|$rawName|$type', () => [])
            .add(stream);
      }

      final tracks = <AudioTrackOption>[];
      for (final entry in groups.entries) {
        final streams = entry.value;
        // Highest-bitrate variant of the language wins.
        streams.sort(
            (a, b) => b.averageBitrate.compareTo(a.averageBitrate));
        final best = streams.first;
        final url = best.url;
        if (url == null || url.isEmpty) continue;
        final locale = (best.audioTrackLocale ?? '').trim();
        final rawName = (best.audioTrackName ?? '').trim();
        final type =
            (best.audioTrackType ?? '').trim().toUpperCase();
        tracks.add(AudioTrackOption(
          id: entry.key,
          label: _audioTrackLabel(rawName, locale, type),
          locale: locale,
          type: type,
          url: url,
        ));
      }

      // Original language first, everything else alphabetical.
      tracks.sort((a, b) {
        if (a.isOriginal != b.isOriginal) return a.isOriginal ? -1 : 1;
        return a.label.compareTo(b.label);
      });
      return tracks;
    } catch (_) {
      return const [];
    }
  }

  String _audioTrackLabel(String rawName, String locale, String type) {
    var base = rawName;
    if (base.isEmpty) base = locale.isEmpty ? 'Default' : locale;
    final lower = base.toLowerCase();
    var suffix = '';
    if (type == 'ORIGINAL' && !lower.contains('original')) {
      suffix = ' (original)';
    } else if (type == 'DUBBED' && !lower.contains('dub')) {
      suffix = ' (dubbed)';
    } else if (type == 'DESCRIPTIVE' && !lower.contains('descri')) {
      suffix = ' (descriptive)';
    }
    return base + suffix;
  }

  /// Audio streams that pair with video, preferring the original language
  /// and skipping descriptive tracks on multi-language videos.
  List<AudioOnlyStream> _audioPool(YoutubeVideo video) {
    final usable = video.audioOnlyStreams
        .where((s) => (s.url ?? '').isNotEmpty)
        .toList();
    if (usable.isEmpty) return usable;
    var pool = usable
        .where(
            (s) => (s.audioTrackType ?? '').toUpperCase() == 'ORIGINAL')
        .toList();
    if (pool.isEmpty) {
      pool = usable
          .where((s) =>
              (s.audioTrackType ?? '').toUpperCase() != 'DESCRIPTIVE')
          .toList();
    }
    return pool.isEmpty ? usable : pool;
  }

  /// Best audio from the pool — container-matched to the video stream when
  /// possible (m4a with mp4, webm with webm), otherwise highest bitrate.
  AudioOnlyStream? _bestAudioFor(
    YoutubeVideo video, {
    String? videoFormatSuffix,
  }) {
    final pool = _audioPool(video);
    if (pool.isEmpty) return null;
    final container = (videoFormatSuffix ?? '').toLowerCase();
    AudioOnlyStream? best;
    for (final s in pool) {
      if (best == null) {
        best = s;
        continue;
      }
      final sMatch = _containerMatches(container, s.formatSuffix);
      final bMatch = _containerMatches(container, best.formatSuffix);
      if ((sMatch && !bMatch) ||
          (sMatch == bMatch && s.averageBitrate > best.averageBitrate)) {
        best = s;
      }
    }
    return best;
  }

  bool _containerMatches(String container, String? audioSuffix) {
    final suffix = (audioSuffix ?? '').toLowerCase();
    if (container.isEmpty || suffix.isEmpty) return true;
    return container == suffix;
  }

  Future<String?> getBestMuxedStreamUrl(String videoUrl) async {
    final streams = await getAvailableStreams(videoUrl);
    if (streams.isEmpty) return null;
    return streams.first.url;
  }

  // ═══════════════════ HELPERS ═══════════════════

  /// Pretty container label (mp4 / webm / 3gp) from the extractor's raw
  /// format suffix/name fields, e.g. `.mp4` or `MPEG-4`.
  String _containerOf(String? formatSuffix, String? formatName) {
    final raw = '${formatSuffix ?? ''} ${formatName ?? ''}'
        .toLowerCase()
        .replaceAll('.', ' ')
        .trim();
    if (raw.contains('webm')) return 'webm';
    if (raw.contains('mpeg') || raw.contains('mp4')) return 'mp4';
    if (raw.contains('3gp')) return '3gp';
    return '';
  }

  String _normalizeQuality(String? raw) {
    if (raw == null || raw.isEmpty) return 'auto';
    final lower = raw.toLowerCase().trim();
    final match = RegExp(r'(\d{3,4})p').firstMatch(lower);
    if (match != null) return '${match.group(1)}p';
    final numMatch = RegExp(r'^(\d{3,4})$').firstMatch(lower);
    if (numMatch != null) return '${numMatch.group(1)}p';
    return raw;
  }

  int _qualityRank(String q) {
    final lower = q.toLowerCase();
    if (lower.contains('2160') || lower.contains('4k')) return 2160;
    if (lower.contains('1440')) return 1440;
    if (lower.contains('1080')) return 1080;
    if (lower.contains('720')) return 720;
    if (lower.contains('480')) return 480;
    if (lower.contains('360')) return 360;
    if (lower.contains('240')) return 240;
    if (lower.contains('144')) return 144;
    return 0;
  }

  bool _isPlayable(VideoItem v) {
    if (v.isLive) return false;
    if (v.id.isEmpty) return false;
    if (v.duration == null) return false;
    if (v.duration!.inSeconds == 0) return false;
    return true;
  }

  String _regionToName(String code) {
    const map = {
      'BD': 'Bangladesh',
      'IN': 'India',
      'US': 'USA',
      'GB': 'UK',
      'PK': 'Pakistan',
      'NP': 'Nepal',
      'LK': 'Sri Lanka',
      'MY': 'Malaysia',
      'SA': 'Saudi Arabia',
      'AE': 'UAE',
      'CA': 'Canada',
      'AU': 'Australia',
      'DE': 'Germany',
      'FR': 'France',
      'JP': 'Japan',
      'KR': 'Korea',
      'ID': 'Indonesia',
      'PH': 'Philippines',
      'TH': 'Thailand',
      'VN': 'Vietnam',
    };
    return map[code] ?? 'World';
  }

  VideoItem _toVideo(dynamic item) {
    final id = item.id ?? '';
    final duration = _toDuration(item.duration);
    final title = (item.name ?? '').toString();
    final isLive = _detectLive(title, duration);
    final itemUrl = (item.url ?? '').toString().toLowerCase();
    final isShort = item.isShort == true ||
        itemUrl.contains('/shorts/') ||
        RegExp(r'(^|\s)#shorts\b', caseSensitive: false).hasMatch(title);

    return VideoItem(
      id: id,
      title: title,
      thumbnailUrl: _extractThumbnail(item),
      uploader: item.uploaderName ?? '',
      uploaderUrl: item.uploaderUrl ?? '',
      uploaderAvatarUrl: _extractUploaderAvatar(item),
      url: 'https://www.youtube.com/watch?v=$id',
      duration: duration,
      viewCount: item.viewCount,
      isLive: isLive,
      isShort: isShort,
    );
  }

  ChannelItem _toChannel(dynamic item) {
    return ChannelItem(
      url: item.url ?? '',
      name: item.name ?? '',
      thumbnailUrl: _extractThumbnail(item),
      subscriberCount: item.subscriberCount,
      description: item.description ?? '',
    );
  }

  bool _detectLive(String title, Duration? duration) {
    if (duration == null) return true;
    if (duration.inSeconds == 0) return true;
    final upper = title.toUpperCase();
    if (upper.contains('LIVE') ||
        upper.contains('🔴') ||
        upper.contains('STREAMING NOW') ||
        upper.contains('#LIVE')) {
      return true;
    }
    return false;
  }

  Duration? _toDuration(dynamic value) {
    if (value == null) return null;
    if (value is Duration) return value;
    if (value is int) return Duration(seconds: value);
    if (value is String) {
      final parts = value.split(':').map(int.tryParse).toList();
      if (parts.isEmpty || parts.any((part) => part == null)) return null;
      var seconds = 0;
      for (final part in parts) {
        seconds = seconds * 60 + part!;
      }
      return Duration(seconds: seconds);
    }
    return null;
  }

  String _extractThumbnail(dynamic item) {
    try {
      final thumbs = item.thumbnails;
      if (thumbs != null && thumbs is List && thumbs.isNotEmpty) {
        for (final thumb in thumbs) {
          final url = thumb?.toString() ?? '';
          if (url.isNotEmpty) return url;
        }
      }
    } catch (_) {}
    return '';
  }

  /// StreamInfoItem exposes `uploaderAvatars` — the channel avatar URLs.
  String _extractUploaderAvatar(dynamic item) {
    try {
      final avatars = item.uploaderAvatars;
      if (avatars != null && avatars is List && avatars.isNotEmpty) {
        for (final avatar in avatars) {
          final url = avatar?.toString() ?? '';
          if (url.isNotEmpty) return url;
        }
      }
    } catch (_) {}
    return '';
  }

  String _firstNonEmpty(List<String> urls) {
    for (final url in urls) {
      if (url.trim().isNotEmpty) return url;
    }
    return '';
  }
}

class ChannelProfile {
  final String name;
  final String avatarUrl;
  final int? subscriberCount;

  const ChannelProfile({
    required this.name,
    required this.avatarUrl,
    this.subscriberCount,
  });
}
