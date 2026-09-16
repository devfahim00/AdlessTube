class VideoItem {
  final String id;
  final String title;
  final String thumbnailUrl;
  final String uploader;
  final String uploaderUrl;
  /// Channel avatar URL when the extractor provided one.
  final String uploaderAvatarUrl;
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
    this.uploaderAvatarUrl = '',
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
        'uploaderAvatarUrl': uploaderAvatarUrl,
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
        uploaderAvatarUrl: map['uploaderAvatarUrl'] ?? '',
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
  /// Container/file type of the stream, e.g. `mp4` or `webm` — shown next
  /// to the quality in menus so users know what will actually play.
  final String container;

  VideoStreamInfo({
    required this.url,
    this.audioUrl,
    required this.quality,
    required this.format,
    this.container = '',
  });
}

/// A selectable audio language (original / dubbed / descriptive) for a video.
class AudioTrackOption {
  /// Stable key, e.g. `en|English original`.
  final String id;
  /// Human label, e.g. `English (original)` or `Bangla (dubbed)`.
  final String label;
  /// BCP-47-ish locale from the extractor, e.g. `en`, `bn`.
  final String locale;
  /// ORIGINAL | DUBBED | DESCRIPTIVE (empty when unknown).
  final String type;
  /// Highest-bitrate stream URL for this track.
  final String url;

  const AudioTrackOption({
    required this.id,
    required this.label,
    required this.locale,
    required this.type,
    required this.url,
  });

  bool get isOriginal => type == 'ORIGINAL';
}

/// What kind of file a download produces.
enum DownloadType {
  /// Muxed file (or paired video+audio files kept together).
  videoAudio,
  /// Video track only, without any audio.
  videoOnly,
  /// Audio track only, downloaded from the video player.
  audio,
  /// Audio track only, downloaded from the music player.
  music,
}

class DownloadItem {
  final String id;
  final String videoId;
  final String title;
  final String uploader;
  final String thumbnailUrl;
  final String videoUrl;
  final DownloadType type;
  final String quality;
  final String? videoPath;
  final String? audioPath;
  final int totalBytes;
  final int receivedBytes;
  /// downloading | completed | failed
  final String status;
  final DateTime createdAt;

  DownloadItem({
    required this.id,
    required this.videoId,
    required this.title,
    required this.uploader,
    this.thumbnailUrl = '',
    required this.videoUrl,
    required this.type,
    this.quality = 'Auto',
    this.videoPath,
    this.audioPath,
    this.totalBytes = 0,
    this.receivedBytes = 0,
    this.status = 'downloading',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  bool get isCompleted => status == 'completed';
  bool get isDownloading => status == 'downloading';
  bool get isFailed => status == 'failed';
  bool get isMusic =>
      type == DownloadType.audio || type == DownloadType.music;
  double get progress =>
      totalBytes > 0 ? (receivedBytes / totalBytes).clamp(0.0, 1.0) : 0.0;

  DownloadItem copyWith({
    String? videoPath,
    String? audioPath,
    int? totalBytes,
    int? receivedBytes,
    String? status,
    String? quality,
  }) =>
      DownloadItem(
        id: id,
        videoId: videoId,
        title: title,
        uploader: uploader,
        thumbnailUrl: thumbnailUrl,
        videoUrl: videoUrl,
        type: type,
        quality: quality ?? this.quality,
        videoPath: videoPath ?? this.videoPath,
        audioPath: audioPath ?? this.audioPath,
        totalBytes: totalBytes ?? this.totalBytes,
        receivedBytes: receivedBytes ?? this.receivedBytes,
        status: status ?? this.status,
        createdAt: createdAt,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'videoId': videoId,
        'title': title,
        'uploader': uploader,
        'thumbnailUrl': thumbnailUrl,
        'videoUrl': videoUrl,
        'type': type.name,
        'quality': quality,
        'videoPath': videoPath,
        'audioPath': audioPath,
        'totalBytes': totalBytes,
        'receivedBytes': receivedBytes,
        'status': status,
        'createdAt': createdAt.toIso8601String(),
      };

  factory DownloadItem.fromMap(Map map) => DownloadItem(
        id: map['id'] ?? '',
        videoId: map['videoId'] ?? '',
        title: map['title'] ?? '',
        uploader: map['uploader'] ?? '',
        thumbnailUrl: map['thumbnailUrl'] ?? '',
        videoUrl: map['videoUrl'] ?? '',
        type: DownloadType.values.firstWhere(
          (t) => t.name == (map['type'] ?? ''),
          orElse: () => DownloadType.videoAudio,
        ),
        quality: map['quality'] ?? 'Auto',
        videoPath: map['videoPath'],
        audioPath: map['audioPath'],
        totalBytes: (map['totalBytes'] as int?) ?? 0,
        receivedBytes: (map['receivedBytes'] as int?) ?? 0,
        status: map['status'] ?? 'downloading',
        createdAt: DateTime.tryParse(map['createdAt'] ?? '') ?? DateTime.now(),
      );
}
