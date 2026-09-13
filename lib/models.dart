class VideoItem {
  final String id;
  final String title;
  final String thumbnailUrl;
  final String uploader;
  final String url;
  final Duration? duration;
  final int? viewCount;

  VideoItem({
    required this.id,
    required this.title,
    required this.thumbnailUrl,
    required this.uploader,
    required this.url,
    this.duration,
    this.viewCount,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'thumbnailUrl': thumbnailUrl,
        'uploader': uploader,
        'url': url,
      };

  factory VideoItem.fromMap(Map map) => VideoItem(
        id: map['id'] ?? '',
        title: map['title'] ?? '',
        thumbnailUrl: map['thumbnailUrl'] ?? '',
        uploader: map['uploader'] ?? '',
        url: map['url'] ?? '',
      );
}
