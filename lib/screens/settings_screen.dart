import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
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
          // ─────────── Appearance ───────────
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Text('Appearance',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          for (final (value, title, subtitle, icon) in const [
            ('auto', 'Auto', 'Use device setting', Icons.brightness_auto),
            ('light', 'Light', 'Bright surfaces', Icons.light_mode),
            ('dark', 'Dark', 'Dark grey surfaces', Icons.dark_mode),
            (
              'black',
              'Pitch Black',
              'True black — ideal for AMOLED screens',
              Icons.contrast
            ),
          ])
            RadioListTile<String>(
              value: value,
              groupValue: storage.themeOption,
              onChanged: (mode) => storage.setThemeOption(mode!),
              title: Text(title),
              subtitle: Text(subtitle),
              secondary: Icon(icon),
            ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('Accent color',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 14,
              runSpacing: 14,
              children: [
                for (final preset in AppTheme.accents)
                  _AccentSwatch(
                    preset: preset,
                    selected: AppTheme.isAccentSelected(
                        storage.accentColor, preset.color),
                    onTap: () =>
                        storage.setAccentColor(preset.color.toARGB32()),
                  ),
              ],
            ),
          ),
          const Divider(),
          // ─────────── Playback ───────────
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
          ListTile(
            leading: const Icon(Icons.aspect_ratio),
            title: const Text('Fullscreen video fit'),
            subtitle: const Text(
                'Fit shows the whole video, Crop zooms to fill, '
                'Stretch distorts to fill'),
            trailing: DropdownButton<String>(
              value: storage.videoFitMode,
              underline: const SizedBox.shrink(),
              items: const [
                DropdownMenuItem(value: 'fit', child: Text('Fit')),
                DropdownMenuItem(value: 'crop', child: Text('Crop')),
                DropdownMenuItem(value: 'stretch', child: Text('Stretch')),
              ],
              onChanged: (mode) {
                if (mode != null) {
                  storage.setVideoFitMode(mode);
                }
              },
            ),
          ),
          const Divider(),
          // ─────────── Animations ───────────
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Text('Animations',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.animation),
            title: const Text('UI animations'),
            subtitle: const Text(
                'Tab switches, page transitions and the mini player animate. '
                'Turn off for instant switches.'),
            value: storage.animationsEnabled,
            onChanged: (enabled) => storage.setAnimationsEnabled(enabled),
          ),
        ],
      ),
    );
  }
}

/// Round accent swatch for the Accent color row; a check marks the
/// active one.
class _AccentSwatch extends StatelessWidget {
  final AccentPreset preset;
  final bool selected;
  final VoidCallback onTap;

  const _AccentSwatch({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Tooltip(
        message: preset.name,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: preset.color,
            border: Border.all(
              color: selected
                  ? (isDark ? Colors.white : Colors.black)
                  : Colors.transparent,
              width: 2.5,
            ),
          ),
          child: selected
              ? const Icon(Icons.check, color: Colors.white, size: 22)
              : null,
        ),
      ),
    );
  }
}
