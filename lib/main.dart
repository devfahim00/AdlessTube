import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';

import 'app_theme.dart';
import 'download_service.dart';
import 'music_playback_service.dart';
import 'region_select_screen.dart';
import 'screens/main_shell.dart';
import 'service_select_screen.dart';
import 'storage_service.dart';
import 'user_profile_service.dart';
import 'video_playback_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  final storage = StorageService();
  await storage.init();
  // The on-device recommendation profile: watch events, feedback
  // signals, channel affinity and topic taste. Built locally, backed up
  // with everything else, never sent anywhere.
  final profile = UserProfileService(storage);
  await profile.init();
  final music = MusicPlaybackService(storage);
  final downloads = DownloadService();
  final videoPlayback = VideoPlaybackService(storage, music, profile);
  // Only one audio surface at a time: starting music (from the app or the
  // notification) closes the video mini player, and opening a video stops
  // music inside the service itself.
  music.onPlaybackStarting = () => unawaited(videoPlayback.close());

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: storage),
        ChangeNotifierProvider.value(value: profile),
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
    final accent = Color(storage.accentColor);
    return MaterialApp(
      title: 'AdlessTube',
      theme: AppTheme.light(accent),
      // Pitch Black is a dark theme with true-black surfaces.
      darkTheme:
          storage.isPitchBlack ? AppTheme.pitchBlack(accent) : AppTheme.dark(accent),
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
