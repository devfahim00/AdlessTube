import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../region_service.dart';
import '../service_select_screen.dart';
import '../storage_service.dart';
import 'downloads_screen.dart';
import 'region_change_screen.dart';
import 'settings_screen.dart';

/// ═══════════════════════ MENU ═══════════════════════
class MenuScreen extends StatelessWidget {
  final Future<void> Function() onCheckForUpdate;

  const MenuScreen({
    super.key,
    required this.onCheckForUpdate,
  });

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    final region = storage.regionCode;

    return Scaffold(
      appBar: AppBar(title: const Text('Menu')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 100),
        children: [
          ListTile(
            leading: const Icon(Icons.public, color: Colors.red),
            title: const Text('Region'),
            subtitle: Text(
              '${RegionService.flagFor(region)} ${RegionService.nameFor(region)}',
              style: TextStyle(color: Colors.grey[500], fontSize: 12),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const RegionChangeScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.download, color: Colors.blue),
            title: const Text('Downloads'),
            subtitle: Text(
              'Your downloaded videos & music',
              style: TextStyle(color: Colors.grey[500], fontSize: 12),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DownloadsScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.apps, color: Colors.orange),
            title: const Text('Services'),
            subtitle: Text(
              _servicesSummary(storage),
              style: TextStyle(color: Colors.grey[500], fontSize: 12),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const ServiceSelectScreen(fromMenu: true),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text('Settings'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.telegram, color: Color(0xFF229ED9)),
            title: const Text('Join Telegram'),
            subtitle: const Text('t.me/projectredfox'),
            trailing: const Icon(Icons.open_in_new),
            onTap: () async {
              await launchUrl(
                Uri.parse('https://t.me/projectredfox'),
                mode: LaunchMode.externalApplication,
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.system_update_outlined),
            title: const Text('Check for update'),
            trailing: const Icon(Icons.chevron_right),
            onTap: onCheckForUpdate,
          ),
          const Divider(),
          // Version auto from pubspec.yaml via package_info_plus
          FutureBuilder<PackageInfo>(
            future: PackageInfo.fromPlatform(),
            builder: (context, snapshot) {
              final version = snapshot.data?.version ?? '...';
              final build = snapshot.data?.buildNumber ?? '';
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'AdlessTube v$version${build.isNotEmpty ? '+$build' : ''}\nAd-free YouTube client',
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

String _servicesSummary(StorageService storage) {
  final names = <String>[];
  if (storage.isServiceEnabled(StorageService.serviceYoutube)) {
    names.add('YouTube');
  }
  if (storage.isServiceEnabled(StorageService.serviceShorts)) {
    names.add('Shorts');
  }
  if (storage.isServiceEnabled(StorageService.serviceMusic)) {
    names.add('Music');
  }
  return names.isEmpty ? 'None' : names.join(', ');
}
