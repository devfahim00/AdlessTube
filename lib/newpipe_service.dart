import 'package:newpipeextractor_dart/newpipeextractor_dart.dart';
import 'models.dart';

class NewPipeService {
  /// অনুসন্ধান
  Future<List<VideoItem>> search(String query) async {
    final response = await SearchExtractor.searchYoutube(
      query,
      [SearchFilter.videos.value],
    );

    final searchResult = response.result;
    if (searchResult == null) return [];

    return searchResult.videos.map(_toVideo).toList();
  }

  /// ট্রেন্ডিং
  Future<List<VideoItem>> getTrending() async {
    final result = await TrendingExtractor.getTrendingVideos();
    return result.items.map(_toVideo).toList();
  }

  /// সবচেয়ে ভালো মিক্সড স্ট্রিম URL পান
  Future<String?> getBestMuxedStreamUrl(String videoUrl) async {
    final video = await VideoExtractor.getStream(videoUrl);
    final muxed = video.videoWithHighestQuality;

    if (muxed == null) return null;

    final url = muxed.url;
    if (url == null || url.isEmpty) return null;

    return url;
  }

  /// চ্যানেলের ভিডিও
  Future<List<VideoItem>> getChannelVideos(String channelUrl) async {
    final result = await ChannelExtractor.getChannelUploads(channelUrl);
    return result.items.map(_toVideo).toList();
  }

  /// StreamInfoItem → VideoItem
  VideoItem _toVideo(dynamic item) {
    final id = item.id ?? '';
    return VideoItem(
      id: id,
      title: item.name ?? '',
      thumbnailUrl: _extractThumbnail(item),
      uploader: item.uploaderName ?? '',
      url: 'https://www.youtube.com/watch?v=$id',
      duration: _toDuration(item.duration),
      viewCount: item.viewCount,
    );
  }

  /// int (seconds) → Duration? convert
  Duration? _toDuration(dynamic value) {
    if (value == null) return null;
    if (value is Duration) return value;
    if (value is int) return Duration(seconds: value);
    return null;
  }

  /// StreamInfoItem থেকে thumbnail URL
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
