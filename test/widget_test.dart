import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:adlesstube/main.dart';
import 'package:adlesstube/download_service.dart';
import 'package:adlesstube/music_playback_service.dart';
import 'package:adlesstube/storage_service.dart';
import 'package:adlesstube/video_playback_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';

class _MockPathProvider extends PathProviderPlatform {
  @override
  Future<String?> getApplicationDocumentsPath() async {
    final dir = await Directory.systemTemp.createTemp('adlesstube_test');
    return dir.path;
  }
}

void main() {
  testWidgets('App launches successfully', (WidgetTester tester) async {
    // Hive performs real file I/O, which needs a real event loop in
    // widget tests — that is what runAsync provides.
    final storage = await tester.runAsync<StorageService>(() async {
      PathProviderPlatform.instance = _MockPathProvider();
      final storage = StorageService();
      await storage.init();
      return storage;
    });
    expect(storage, isNotNull);

    final music = MusicPlaybackService(storage!);
    final downloads = DownloadService();
    final videoPlayback = VideoPlaybackService(storage, music);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: storage),
          ChangeNotifierProvider.value(value: music),
          ChangeNotifierProvider.value(value: downloads),
          ChangeNotifierProvider.value(value: videoPlayback),
        ],
        child: const AdlessTubeApp(),
      ),
    );
    await tester.pump();

    // First launch (no region picked yet) shows the region picker.
    expect(find.text('Select Your Region'), findsOneWidget);
  });
}
