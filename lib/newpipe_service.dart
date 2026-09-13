import 'package:newpipeextractor_dart/newpipeextractor_dart.dart';
import 'models.dart';

class NewPipeService {
  /// অনুসন্ধান — SearchResult.videos field ব্যবহার করে
  Future<List<VideoItem>> search(String query) async {
    final response = await SearchExtractor.searchYoutube(
      query,
      [SearchFilter.videos.value],
    );

    // response একটি record: ({PageToken? next, SearchResult result})
    final searchResult = response.result;

    // SearchResult-এ items/relatedStreams নেই — videos আছে
    final videos = searchResult.videos;
    return videos.map(_toVideo).toList();
  }

  /// ট্রেন্ডিং — record থেকে সরাসরি items
  Future<List<VideoItem>> getTrending() async {
    // TrendingExtractor.getTrendingVideos() returns:
    //   ({List<StreamInfoItem> items, PageToken? next})
    final result = await TrendingExtractor.getTrendingVideos();
    return result.items.map(_toVideo).toList();
  }

  /// সবচেয়ে ভালো মিক্সড স্ট্রিম URL পান (সর্বোচ্চ 720p)
  /// মিক্সড স্ট্রিম না থাকলে null ফেরত দেয়
  Future<String?> getBestMuxedStreamUrl(String videoUrl) async {
    final video = await VideoExtractor.getStream(videoUrl);
    final muxed = video.videoWithHighestQuality;

    if (muxed == null) return null;

    // url nullable, তাই null-safe চেক
    final url = muxed.url;
    if (url == null || url.isEmpty) return null;

    return url;
  }

  /// চ্যানেলের ভিডিও তালিকা
  Future<List<VideoItem>> getChannelVideos(String channelUrl) async {
    // ChannelExtractor.getChannelUploads() returns record:
    //   ({List<StreamInfoItem> items, PageToken? next})
    final result = await ChannelExtractor.getChannelUploads(channelUrl);
    return result.items.map(_toVideo).toList();
  }

  /// StreamInfoItem → VideoItem
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
