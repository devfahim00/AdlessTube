class VideoItem {
  final String id;
  final String title;
  final String thumbnailUrl;
  final String uploader;
  final String uploaderUrl;
  final String url;
  final Duration? duration;
  final int? viewCount;
  final bool isLive;
  final bool isShort;

  VideoItem({
    required this.id,
    required this.title,
    required this.thumbnailUrl,
    required this.uploader,
    this.uploaderUrl = '',
    required this.url,
    this.duration,
    this.viewCount,
    this.isLive = false,
    this.isShort = false,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'thumbnailUrl': thumbnailUrl,
        'uploader': uploader,
        'uploaderUrl': uploaderUrl,
        'url': url,
        'durationSeconds': duration?.inSeconds,
        'isLive': isLive,
        'isShort': isShort,
      };

  factory VideoItem.fromMap(Map map) => VideoItem(
        id: map['id'] ?? '',
        title: map['title'] ?? '',
        thumbnailUrl: map['thumbnailUrl'] ?? '',
        uploader: map['uploader'] ?? '',
        uploaderUrl: map['uploaderUrl'] ?? '',
    url: map['url'] ?? '',
    duration: map['durationSeconds'] is int
        ? Duration(seconds: map['durationSeconds'] as int)
        : null,
    isLive: map['isLive'] ?? false,
    isShort: map['isShort'] ?? false,
      );
}

class ChannelItem {
  final String url;
  final String name;
  final String thumbnailUrl;
  final int? subscriberCount;
  final String description;

  ChannelItem({
    required this.url,
    required this.name,
    this.thumbnailUrl = '',
    this.subscriberCount,
    this.description = '',
  });
}

class VideoStreamInfo {
  final String url;
  /// Separate audio URL for YouTube's adaptive (video-only) streams.
  final String? audioUrl;
  final String quality;
  final String format;

  VideoStreamInfo({
    required this.url,
    this.audioUrl,
    required this.quality,
    required this.format,
  });
}
