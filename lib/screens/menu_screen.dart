import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../region_service.dart';
import '../service_select_screen.dart';
import '../storage_service.dart';
import 'downloads_screen.dart';
import 'region_change_screen.dart';
import 'settings_screen.dart';

/// ═══════════════════════ MENU ═══════════════════════
class MenuScreen extends StatefulWidget {
  final Future<void> Function() onCheckForUpdate;

  const MenuScreen({
    super.key,
    required this.onCheckForUpdate,
  });

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  Future<void> _exportData() async {
    final storage = context.read<StorageService>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final data = await storage.exportData();
      final json = const JsonEncoder.withIndent('  ').convert(data);
      final stamp = DateTime.now()
          .toIso8601String()
          .split('T')
          .first; // 2026-09-16
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/adlesstube_backup_$stamp.json');
      await file.writeAsString(json);
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/json')],
        subject: 'AdlessTube backup $stamp',
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Export failed — please try again.')),
      );
    }
  }


  Future<void> _importData() async {
    final storage = context.read<StorageService>();
    final messenger = ScaffoldMessenger.of(context);

    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: false,
    );
    if (!mounted) return;
    final path = picked?.files.single.path;
    if (path == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Import backup?'),
        content: const Text(
          'Your history, subscriptions, saved videos, liked songs, search '
          'history, playback progress and settings from this backup will be '
          'restored. Existing entries with the same key are replaced.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Import'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final json = await File(path).readAsString();
      final data = jsonDecode(json);
      if (data is! Map<String, dynamic>) {
        throw const FormatException('Not an AdlessTube backup file.');
      }
      final restored = await storage.importData(data);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
              'Imported $restored entries — everything is back like before.'),
        ),
      );
    } on FormatException {
      messenger.showSnackBar(
        const SnackBar(
            content: Text('That file is not a valid AdlessTube backup.')),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Import failed — please try again.')),
      );
    }
  }


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
            leading: Icon(Icons.public,
                color: Theme.of(context).colorScheme.primary),
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
            leading: const Icon(Icons.upload_file, color: Colors.green),
            title: const Text('Export data'),
            subtitle: Text(
              'Save a backup of history, subscriptions & settings',
              style: TextStyle(color: Colors.grey[500], fontSize: 12),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _exportData(),
          ),
          ListTile(
            leading: const Icon(Icons.restore, color: Colors.teal),
            title: const Text('Import data'),
            subtitle: Text(
              'Restore everything from a backup file',
              style: TextStyle(color: Colors.grey[500], fontSize: 12),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _importData(),
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
            onTap: widget.onCheckForUpdate,
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
