import 'package:newpipeextractor_dart/newpipeextractor_dart.dart';
import 'models.dart';

class NewPipeService {
  /// অনুসন্ধান
  Future<List<VideoItem>> search(String query) async {
    // SearchExtractor.searchYoutube() returns:
    //   ({PageToken? next, SearchResult result})
    final response = await SearchExtractor.searchYoutube(
      query,
      [SearchFilter.videos.value],
    );

    // Record থেকে result বের করুন, তারপর items
    final searchResult = response.result;
    if (searchResult == null) return [];

    return searchResult.items.map(_toVideo).toList();
  }

  /// ট্রেন্ডিং
  Future<List<VideoItem>> getTrending() async {
    // TrendingExtractor.getTrendingVideos() returns record:
    //   ({List<StreamInfoItem> items, PageToken? next})
    final result = await TrendingExtractor.getTrendingVideos();
    return result.items.map(_toVideo).toList();
  }

  /// সবচেয়ে ভালো মিক্সড স্ট্রিম URL পান
  Future<String?> getBestMuxedStreamUrl(String videoUrl) async {
    final video = await VideoExtractor.getStream(videoUrl);
    final muxed = video.videoWithHighestQuality;

    if (muxed == null) return null;

    final url = muxed.url;
    if (url.isEmpty) return null;

    return url;
  }

  /// চ্যানেলের ভিডিও
  Future<List<VideoItem>> getChannelVideos(String channelUrl) async {
    // ChannelExtractor.getChannelUploads() returns record:
    //   ({List<StreamInfoItem> items, PageToken? next})
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
