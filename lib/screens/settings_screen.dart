import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../storage_service.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Text('Appearance',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          RadioListTile<ThemeMode>(
            value: ThemeMode.system,
            groupValue: storage.themeMode,
            onChanged: (mode) => storage.setThemeMode(mode!),
            title: const Text('Auto'),
            subtitle: const Text('Use device setting'),
          ),
          RadioListTile<ThemeMode>(
            value: ThemeMode.light,
            groupValue: storage.themeMode,
            onChanged: (mode) => storage.setThemeMode(mode!),
            title: const Text('Light'),
          ),
          RadioListTile<ThemeMode>(
            value: ThemeMode.dark,
            groupValue: storage.themeMode,
            onChanged: (mode) => storage.setThemeMode(mode!),
            title: const Text('Dark'),
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Text('Playback',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          ListTile(
            leading: const Icon(Icons.high_quality),
            title: const Text('Default video quality'),
            subtitle:
                const Text('Uses the selected quality or the next lower one'),
            trailing: DropdownButton<String>(
              value: storage.defaultQuality,
              underline: const SizedBox.shrink(),
              items: const [
                'Auto',
                '144p',
                '240p',
                '360p',
                '480p',
                '720p',
                '1080p',
                '1440p',
                '2160p'
              ]
                  .map((quality) => DropdownMenuItem(
                        value: quality,
                        child: Text(quality),
                      ))
                  .toList(),
              onChanged: (quality) {
                if (quality != null) {
                  storage.setDefaultQuality(quality);
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
