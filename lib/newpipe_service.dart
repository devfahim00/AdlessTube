import 'package:newpipeextractor_dart/newpipeextractor_dart.dart';
import 'models.dart';

class NewPipeService {
  /// ─── অনুসন্ধান ───
  Future<List<VideoItem>> search(String query) async {
    final response = await SearchExtractor.searchYoutube(
      query,
      [SearchFilter.videos.value],
    );

    // response.result কখনো null হয় না, তাই সরাসরি ব্যবহার
    final searchResult = response.result;
    final videos = searchResult?.videos ?? [];
    return videos
        .map(_toVideo)
        .where((v) => !v.isLive)
        .toList();
  }

  /// ─── ট্রেন্ডিং (region অনুযায়ী) ───
  Future<List<VideoItem>> getTrending({String region = 'US'}) async {
    try {
      final result = await TrendingExtractor.getTrendingVideos();
      final items = result.items.map(_toVideo).where((v) => !v.isLive).toList();
      if (items.isNotEmpty) return items;
    } catch (_) {}

    // Fallback: region-specific trending search
    return _trendingFallback(region);
  }

  Future<List<VideoItem>> _trendingFallback(String region) async {
    final regionName = _regionToName(region);
    final queries = [
      '$regionName trending',
      '$regionName popular',
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
        final vids = res.result?.videos ?? [];
        for (final v in vids) {
          final item = _toVideo(v);
          if (!item.isLive && !seen.contains(item.id)) {
            seen.add(item.id);
            all.add(item);
          }
        }
      } catch (_) {}
    }
    return all;
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

  /// ─── Channel এর ভিডিও ───
  Future<List<VideoItem>> getChannelVideos(String channelUrl) async {
    try {
      final result = await ChannelExtractor.getChannelUploads(channelUrl);
      return result.items
          .map(_toVideo)
          .where((v) => !v.isLive)
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// ─── Related videos (video page এর নিচে) ───
  /// ServiceExtractor.getRelatedItems ব্যবহার করে।
  /// YouTube এর serviceId = 0
  Future<List<VideoItem>> getRelatedVideos(String videoUrl) async {
    try {
      final response = await ServiceExtractor.getRelatedItems(0, videoUrl);
      // response একটি SearchResult — videos property আছে
      final videos = response.videos ?? [];
      return videos
          .map(_toVideo)
          .where((v) => !v.isLive && v.id.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// ─── সব quality stream URL পাওয়া (muxed + video-only) ───
  Future<List<VideoStreamInfo>> getAvailableStreams(String videoUrl) async {
    final video = await VideoExtractor.getStream(videoUrl);
    final streams = <VideoStreamInfo>[];

    // Muxed streams (video + audio একসাথে)
    final videoStreams = video.videoStreams ?? [];
    for (final s in videoStreams) {
      final url = s.url;
      if (url.isEmpty) continue;
      final quality = s.resolution ?? _bitrateToQuality(s.bitrate);
      streams.add(VideoStreamInfo(
        url: url,
        quality: quality,
        format: 'muxed',
        bitrate: s.bitrate,
      ));
    }

    // Muxed না থাকলে videoWithHighestQuality fallback
    if (streams.isEmpty) {
      final muxed = video.videoWithHighestQuality;
      final muxedUrl = muxed.url;
      if (muxedUrl != null && muxedUrl.isNotEmpty) {
        streams.add(VideoStreamInfo(
          url: muxedUrl,
          quality: muxed.resolution ?? 'auto',
          format: 'muxed',
        ));
      }
    }

    // Quality অনুযায়ী sort (উচ্চ থেকে নিচ)
    streams.sort((a, b) =>
        _qualityRank(b.quality).compareTo(_qualityRank(a.quality)));
    return streams;
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

  String _bitrateToQuality(int? bitrate) {
    if (bitrate == null) return 'auto';
    if (bitrate > 4000000) return '1080p';
    if (bitrate > 2000000) return '720p';
    if (bitrate > 1000000) return '480p';
    if (bitrate > 500000) return '360p';
    return '240p';
  }

  /// ─── Backward-compatible ───
  Future<String?> getBestMuxedStreamUrl(String videoUrl) async {
    final streams = await getAvailableStreams(videoUrl);
    if (streams.isEmpty) return null;
    return streams.first.url;
  }

  /// ─── StreamInfoItem → VideoItem ───
  VideoItem _toVideo(dynamic item) {
    final id = item.id ?? '';
    final isLive = _detectLive(item);

    return VideoItem(
      id: id,
      title: item.name ?? '',
      thumbnailUrl: _extractThumbnail(item),
      uploader: item.uploaderName ?? '',
      uploaderUrl: item.uploaderUrl ?? '',
      url: 'https://www.youtube.com/watch?v=$id',
      duration: _toDuration(item.duration),
      viewCount: item.viewCount,
      isLive: isLive,
    );
  }

  bool _detectLive(dynamic item) {
    try {
      final d = item.duration;
      if (d == null) return true;
      if (d is Duration && d.inSeconds == 0) return true;
      if (d is int && d == 0) return true;
    } catch (_) {}
    final title = (item.name ?? '').toString().toUpperCase();
    if (title.contains('🔴') || title.contains('LIVE')) return true;
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
