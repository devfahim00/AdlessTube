import 'package:newpipeextractor_dart/newpipeextractor_dart.dart';
import 'models.dart';

class NewPipeService {
  /// অনুসন্ধান
  Future<List<VideoItem>> search(String query) async {
    final result = await SearchExtractor.searchYoutube(
      query,
      [SearchFilter.videos.value],
    );
    // Handle the actual return type from searchYoutube
    // You may need to check what SearchExtractor.searchYoutube actually returns
    final items = result is SearchResult ? result.items : result.result?.items ?? [];
    return items.map(_toVideo).toList();
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

    // Null-check the url before calling isEmpty
    final url = muxed.url;
    if (url == null || url.isEmpty) return null;

    return url;
  }

  /// চ্যানেলের ভিডিও তালিকা
  Future<List<VideoItem>> getChannelVideos(String channelUrl) async {
    final result = await ChannelExtractor.getChannelUploads(channelUrl);
    return result.items.map(_toVideo).toList();
  }

  VideoItem _toVideo(dynamic item) {
    final id = item.id ?? '';
    return VideoItem(
      id: id,
      title: item.name ?? '',
      thumbnailUrl: item.thumbnailUrl ?? '',
      uploader: item.uploaderName ?? '',
      url: 'https://www.youtube.com/watch?v=$id',
      duration: item.duration,
      viewCount: item.viewCount,
    );
  }
}
