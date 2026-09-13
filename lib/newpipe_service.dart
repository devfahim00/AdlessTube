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

    final videos = searchResult.videos;
    return videos.map(_toVideo).toList();
  }

  /// ট্রেন্ডিং
  Future<List<VideoItem>> getTrending() async {
    final result = await TrendingExtractor.getTrendingVideos();
    return result.items.map(_toVideo).toList();
  }

  /// সবচেয়ে ভালো মিক্সড স্ট্রিম URL পান (সর্বোচ্চ 720p)
  Future<String?> getBestMuxedStreamUrl(String videoUrl) async {
    final video = await VideoExtractor.getStream(videoUrl);
    final muxed = video.videoWithHighestQuality;

    if (muxed == null) return null;

    final url = muxed.url;
    if (url == null || url.isEmpty) return null;

    return url;
  }

  /// চ্যানেলের ভিডিও তালিকা
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
      thumbnailUrl: _extractThumbnail(item), // 🔧 পরিবর্তিত অংশ
      uploader: item.uploaderName ?? '',
      url: 'https://www.youtube.com/watch?v=$id',
      duration: item.duration,
      viewCount: item.viewCount,
    );
  }

  /// StreamInfoItem থেকে থাম্বনেইল URL নিরাপদে বের করুন
  String _extractThumbnail(dynamic item) {
    try {
      // thumbnails হলো List<String>, তাই প্রথম আইটেমটি ব্যবহার করতে হবে
      final thumbs = item.thumbnails;
      if (thumbs != null && thumbs is List && thumbs.isNotEmpty) {
        return thumbs.first.toString();
      }
    } catch (_) {
      // কোনো কারণে ব্যর্থ হলে খালি স্ট্রিং রিটার্ন করবে
    }
    return '';
  }
}
