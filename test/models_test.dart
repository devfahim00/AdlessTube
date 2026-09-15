import 'package:flutter_test/flutter_test.dart';
import 'package:adlesstube/models.dart';

void main() {
  test('DownloadItem map roundtrip', () {
    final item = DownloadItem(
      id: 'x_videoAudio',
      videoId: 'x',
      title: 'Test',
      uploader: 'Chan',
      videoUrl: 'https://www.youtube.com/watch?v=x',
      type: DownloadType.videoAudio,
      quality: '720p',
      status: 'completed',
    );
    final restored = DownloadItem.fromMap(item.toMap());
    expect(restored.id, 'x_videoAudio');
    expect(restored.type, DownloadType.videoAudio);
    expect(restored.quality, '720p');
    expect(restored.isCompleted, true);
    expect(restored.isMusic, false);
  });

  test('Music item is music', () {
    final item = DownloadItem.fromMap({
      'id': 'y_music',
      'videoId': 'y',
      'title': 'Song',
      'uploader': 'A',
      'videoUrl': 'u',
      'type': 'music',
    });
    expect(item.isMusic, true);
    expect(item.type, DownloadType.music);
  });
}
