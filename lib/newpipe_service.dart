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

  /// Channel uploads — multiple fallback method
  Future<List<VideoItem>> getChannelVideos(String channelUrl) async {
    // ── Attempt 1: ChannelExtractor.getChannelUploads ──
    try {
      final result = await ChannelExtractor.getChannelUploads(channelUrl);
      final items = result.items.map(_toVideo).where(_isPlayable).toList();
      if (items.isNotEmpty) return items;
    } catch (_) {}

    // ── Attempt 2: ServiceExtractor.getChannelUploads (0 = YouTube) ──
    try {
      final result = await ServiceExtractor.getChannelUploads(0, channelUrl);
      final items = result.items.map(_toVideo).where(_isPlayable).toList();
      if (items.isNotEmpty) return items;
    } catch (_) {}

    // ── Attempt 3: Channel info + related extraction ──
    try {
      final channel = await ChannelExtractor.getChannel(channelUrl);
      final items =
          channel.relatedStreams.map(_toVideo).where(_isPlayable).toList();
      if (items.isNotEmpty) return items;
    } catch (_) {}

    return [];
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

  // ═══════════════════ STREAMS (HD via video+audio merge) ═══════════════════

  /// সব available quality level return করে।
  /// প্রতিটা level এ video URL এবং audio URL আলাদা করে দেয়,
  /// যাতে Player.open([video, audio]) merge করতে পারে।
  Future<List<VideoStreamInfo>> getAvailableStreams(String videoUrl) async {
    final video = await VideoExtractor.getStream(videoUrl);

    // ── Audio stream collect (best audio) ──
    // Prefer muxed এর ভেতরে audio থাকে, কিন্তু video-only এর সাথে audio merge করতে হবে
    String? bestAudioUrl;
    try {
      final audioStreams = video.audioStreams ?? [];
      if (audioStreams.isNotEmpty) {
        // Highest bitrate audio খুঁজি
        final sorted = audioStreams.toList()
          ..sort((a, b) => (b.bitrate ?? 0).compareTo(a.bitrate ?? 0));
        bestAudioUrl = sorted.first.url;
      } else {
        final audio = video.audioWithHighestQuality;
        bestAudioUrl = audio?.url;
      }
    } catch (_) {}

    // ── Muxed streams (সাধারণত 360p max) ──
    final Map<String, VideoStreamInfo> result = {};

    try {
      final muxedList = video.videoStreams ?? [];
      for (final s in muxedList) {
        final url = s.url;
        if (url == null || url.isEmpty) continue;
        final q = _normalizeQuality(s.resolution);
        result[q] = VideoStreamInfo(
          url: url,
          quality: q,
          format: 'muxed',
        );
      }
    } catch (_) {}

    // ── Video-only streams (HD possible) — audio merge করব ──
    try {
      final videoOnly = video.videoOnlyStreams ?? [];
      for (final s in videoOnly) {
        final vUrl = s.url;
        if (vUrl == null || vUrl.isEmpty) continue;
        final q = _normalizeQuality(s.resolution);
        // muxed এ same quality না থাকলে video-only add করি
        if (!result.containsKey(q)) {
          result[q] = VideoStreamInfo(
            url: vUrl,
            quality: q,
            format: 'video-only',
            audioUrl: bestAudioUrl,
          );
        }
      }
    } catch (_) {}

    // ── videoWithHighestQuality fallback ──
    if (result.isEmpty) {
      try {
        final muxed = video.videoWithHighestQuality;
        final muxedUrl = muxed.url;
        if (muxedUrl.isNotEmpty) {
          final q = _normalizeQuality(muxed.resolution);
          result[q] = VideoStreamInfo(
            url: muxedUrl,
            quality: q,
            format: 'muxed',
          );
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
