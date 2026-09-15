import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';
import 'screens.dart';
import 'music_playback_service.dart';
import 'storage_service.dart';
import 'region_select_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  final storage = StorageService();
  await storage.init();
  final music = await MusicPlaybackService.create(storage);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: storage),
        ChangeNotifierProvider.value(value: music),
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
    return const MainShell();
  }
}
