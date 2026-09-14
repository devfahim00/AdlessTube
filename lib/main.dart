import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';
import 'screens.dart';
import 'storage_service.dart';
import 'region_select_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  final storage = StorageService();
  await storage.init();

  runApp(
    ChangeNotifierProvider.value(
      value: storage,
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
      darkTheme: ThemeData.dark(useMaterial3: true, colorSchemeSeed: Colors.red),
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
