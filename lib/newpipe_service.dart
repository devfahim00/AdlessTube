import 'package:newpipeextractor_dart/newpipeextractor_dart.dart';
import 'models.dart';

class NewPipeService {
  /// অনুসন্ধান
  Future<List<VideoItem>> search(String query) async {
    final response = await SearchExtractor.searchYoutube(
      query,
      [SearchFilter.videos.value],
    );

    // response একটি record: ({PageToken? next, SearchResult result})
    final searchResult = response.result;

    // SearchResult-এ items getter না থাকলে অন্য field ব্যবহার করুন
    // সবচেয়ে safe: relatedStreams অথবা videos
    final items = searchResult.relatedStreams;

    return items.map(_toVideo).toList();
  }

  /// ট্রেন্ডিং
  Future<List<VideoItem>> getTrending() async {
    // getTrendingVideos returns record: ({List<StreamInfoItem> items, PageToken? next})
    final result = await TrendingExtractor.getTrendingVideos();
    return result.items.map(_toVideo).toList();
  }

  /// সবচেয়ে ভালো মিক্সড স্ট্রিম URL পান
  Future<String?> getBestMuxedStreamUrl(String videoUrl) async {
    final video = await VideoExtractor.getStream(videoUrl);
    final muxed = video.videoWithHighestQuality;

    if (muxed == null) return null;

    // url nullable, তাই safe access
    final url = muxed.url;
    if (url == null || url.isEmpty) return null;

    return url;
  }

  /// চ্যানেলের ভিডিও
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
