import 'package:newpipeextractor_dart/newpipeextractor_dart.dart';
import 'models.dart';

class NewPipeService {
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

  Future<List<VideoItem>> getShorts({
    required String region,
    List<String> subscribedChannels = const [],
  }) async {
    final seen = <String>{};
    final shorts = <VideoItem>[];

    void addAll(Iterable<VideoItem> items) {
      for (final item in items) {
        if (!item.isLive && seen.add(item.id)) shorts.add(item);
      }
    }

    for (final url in subscribedChannels.take(4)) {
      try {
        final page = await getChannelTabPage(url, 'shorts');
        addAll(page.items);
      } catch (_) {}
    }

    final regionName = _regionToName(region);
    for (final query in ['$regionName shorts', 'popular shorts $regionName']) {
      try {
        final page = await searchVideoPage(query);
        addAll(page.items);
      } catch (_) {}
    }
    return shorts;
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
    final page = next == null
        ? await ChannelExtractor.getChannelTabContent(channelUrl, tab)
        : await ChannelExtractor.getChannelTabNextPage(channelUrl, tab, next);
    return (
      items: page.streams.map(_toVideo).where(_isPlayable).toList(),
      next: page.next,
    );
  }

  // ═══════════════════ RELATED ═══════════════════

  Future<List<VideoItem>> getRelatedVideos(String videoUrl) async {
    try {
      final response = await ServiceExtractor.getRelatedItems(0, videoUrl);
      return response.videos.map(_toVideo).where(_isPlayable).toList();
    } catch (_) {
      return [];
    }
  }

  // ═══════════════════ STREAMS ═══════════════════

  /// Muxed streams return করি। Video-only merge টা YouTube এ
  /// muxed 360p এ cap থাকে — এটাই সবচেয়ে stable।
  /// Higher quality পেতে চাইলে ভবিষ্যতে youtube_explode_dart use করতে হবে।
  Future<List<VideoStreamInfo>> getAvailableStreams(String videoUrl) async {
    final video = await VideoExtractor.getStream(videoUrl);
    final Map<String, VideoStreamInfo> result = {};

    // YouTube exposes HD formats as video-only DASH streams. Pair each one
    // with matching audio so media_kit/mpv can play it with sound.
    try {
      for (final stream in video.videoOnlyStreams) {
        final videoOnlyUrl = stream.url;
        final audioUrl = video.bestAudioForVideo(stream)?.url;
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
        );
      }
    } catch (_) {}

    // ── Muxed streams ──
    try {
      final muxedList = video.videoStreams ?? [];
      for (final s in muxedList) {
        final url = s.url;
        if (url == null || url.isEmpty) continue;
        final q = _normalizeQuality(s.resolution);
        result['$q-muxed'] = VideoStreamInfo(
          url: url,
          quality: q,
          format: 'muxed',
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

  Future<String?> getBestMuxedStreamUrl(String videoUrl) async {
    final streams = await getAvailableStreams(videoUrl);
    if (streams.isEmpty) return null;
    return streams.first.url;
  }

  // ═══════════════════ HELPERS ═══════════════════

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

    return VideoItem(
      id: id,
      title: title,
      thumbnailUrl: _extractThumbnail(item),
      uploader: item.uploaderName ?? '',
      uploaderUrl: item.uploaderUrl ?? '',
      url: 'https://www.youtube.com/watch?v=$id',
      duration: duration,
      viewCount: item.viewCount,
      isLive: isLive,
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
    return null;
  }

  String _extractThumbnail(dynamic item) {
    try {
      final thumbs = item.thumbnails;
      if (thumbs != null && thumbs is List && thumbs.isNotEmpty) {
        return thumbs.first.toString();
      }
    } catch (_) {}
    return '';
  }
}
