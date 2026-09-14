import 'package:newpipeextractor_dart/newpipeextractor_dart.dart';
import 'models.dart';

/// Search result type enum
enum SearchType { video, channel }

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

  // ═══════════════════ TRENDING (Region-aware) ═══════════════════

  Future<List<VideoItem>> getTrending({String region = 'US'}) async {
    // region name থেকে query build করি
    final regionName = _regionToName(region);
    final queries = [
      '$regionName trending videos',
      '$regionName popular',
      '$regionName news',
      '$regionName music',
      '$regionName songs',
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

  Future<List<VideoItem>> getChannelVideos(String channelUrl) async {
    try {
      final result = await ChannelExtractor.getChannelUploads(channelUrl);
      return result.items.map(_toVideo).where(_isPlayable).toList();
    } catch (_) {
      return [];
    }
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

  // ═══════════════════ STREAMS (max quality) ═══════════════════

  /// সব available muxed stream + fallback।
  /// YouTube সাধারণত 360p এর বেশি muxed দেয় না,
  /// তাই max quality পেতে video-only + audio merge দরকার।
  /// এখানে আমরা সব muxed + video-only option list করছি।
  Future<List<VideoStreamInfo>> getAvailableStreams(String videoUrl) async {
    final video = await VideoExtractor.getStream(videoUrl);
    final Map<String, VideoStreamInfo> unique = {};

    // ── Muxed streams ──
    final muxedStreams = video.videoStreams ?? [];
    for (final s in muxedStreams) {
      final url = s.url;
      if (url == null || url.isEmpty) continue;
      final q = _normalizeQuality(s.resolution);
      unique[q] = VideoStreamInfo(
        url: url,
        quality: q,
        format: 'muxed',
      );
    }

    // ── videoWithHighestQuality fallback ──
    if (unique.isEmpty) {
      final muxed = video.videoWithHighestQuality;
      final muxedUrl = muxed?.url;
      if (muxedUrl != null && muxedUrl.isNotEmpty) {
        final q = _normalizeQuality(muxed?.resolution);
        unique[q] = VideoStreamInfo(
          url: muxedUrl,
          quality: q,
          format: 'muxed',
        );
      }
    }

    final list = unique.values.toList();
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
    // "720p" / "720p60" → "720p"
    final match = RegExp(r'(\d{3,4})p').firstMatch(lower);
    if (match != null) return '${match.group(1)}p';
    // "1080" → "1080p"
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

  /// ⚠️ শুধুমাত্র সেগুলো return করি যেগুলো live না এবং playable
  bool _isPlayable(VideoItem v) {
    if (v.isLive) return false;
    if (v.id.isEmpty) return false;
    // duration 0 বা null হলে live/short হতে পারে
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
    // duration null → live/short
    if (duration == null) return true;
    // duration 0 → live
    if (duration.inSeconds == 0) return true;
    // title keyword check
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
