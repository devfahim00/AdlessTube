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
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'thumbnailUrl': thumbnailUrl,
        'uploader': uploader,
        'uploaderUrl': uploaderUrl,
        'url': url,
        'isLive': isLive,
      };

  factory VideoItem.fromMap(Map map) => VideoItem(
        id: map['id'] ?? '',
        title: map['title'] ?? '',
        thumbnailUrl: map['thumbnailUrl'] ?? '',
        uploader: map['uploader'] ?? '',
        uploaderUrl: map['uploaderUrl'] ?? '',
        url: map['url'] ?? '',
        isLive: map['isLive'] ?? false,
      );
}

/// Player এ quality select করার জন্য
class VideoStreamInfo {
  final String url;
  final String quality; // e.g. "720p", "1080p", "480p"
  final String format; // "muxed" / "video" / "audio"

  VideoStreamInfo({
    required this.url,
    required this.quality,
    required this.format,
  });
}
