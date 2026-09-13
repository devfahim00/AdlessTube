import 'package:newpipeextractor_dart/newpipeextractor_dart.dart';
import 'models.dart';

class NewPipeService {
  /// অনুসন্ধান
  Future<List<VideoItem>> search(String query) async {
    final page = await SearchExtractor.searchYoutube(
      query,
      [SearchFilter.videos.value],
    );
    return page.items.map(_toVideo).toList();
  }

  /// ট্রেন্ডিং
  Future<List<VideoItem>> getTrending() async {
    final page = await TrendingExtractor.getTrendingVideos();
    return page.items.map(_toVideo).toList();
  }

  /// সবচেয়ে ভালো মিক্সড স্ট্রিম URL পান (সর্বোচ্চ 720p)
  /// মিক্সড স্ট্রিম না থাকলে null ফেরত দেয়
  Future<String?> getBestMuxedStreamUrl(String videoUrl) async {
    final video = await VideoExtractor.getStream(videoUrl);
    final muxed = video.videoWithHighestQuality;
    if (muxed != null && muxed.url.isNotEmpty) {
      return muxed.url;
    }
    return null;
  }

  /// চ্যানেলের ভিডিও তালিকা
  Future<List<VideoItem>> getChannelVideos(String channelUrl) async {
    final page = await ChannelExtractor.getChannelUploads(channelUrl);
    return page.items.map(_toVideo).toList();
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
