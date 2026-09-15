import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';

import 'download_service.dart';
import 'music_playback_service.dart';
import 'region_select_screen.dart';
import 'screens/main_shell.dart';
import 'service_select_screen.dart';
import 'storage_service.dart';
import 'video_playback_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  final storage = StorageService();
  await storage.init();
  final music = MusicPlaybackService(storage);
  final downloads = DownloadService();
  final videoPlayback = VideoPlaybackService(storage, music);
  // Only one audio surface at a time: starting music (from the app or the
  // notification) closes the video mini player, and opening a video stops
  // music inside the service itself.
  music.onPlaybackStarting = () => unawaited(videoPlayback.close());

  runApp(
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
}

class AdlessTubeApp extends StatelessWidget {
  const AdlessTubeApp({super.key});

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    return MaterialApp(
      title: 'AdlessTube',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.red),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.red,
      ),
      themeMode: storage.themeMode,
      debugShowCheckedModeBanner: false,
      home: const _RootRouter(),
    );
  }
}

class _RootRouter extends StatelessWidget {
  const _RootRouter();

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    if (!storage.hasSelectedRegion) {
      return const RegionSelectScreen();
    }
    if (!storage.hasSelectedServices) {
      return const ServiceSelectScreen();
    }
    return const MainShell();
  }
}
