import 'package:flutter/material.dart';

/// App theming: light / dark / pitch-black (AMOLED) themes built from a
/// user-selected accent color.
///
/// The accent is forced into `ColorScheme.primary` so the whole UI keeps
/// the same vivid brand color the app has always used (instead of the
/// pastel tone Material 3 would normally derive from the seed in dark
/// mode). Picking a different accent instantly recolors the entire app.
class AppTheme {
  /// The classic AdlessTube red — the default accent.
  static const defaultAccent = Color(0xFFF44336);

  /// Accent presets offered in Settings ▸ Appearance.
  ///
  /// All of them work with white foreground text on top.
  static const accents = <AccentPreset>[
    AccentPreset('Red', Color(0xFFF44336)),
    AccentPreset('Blue', Color(0xFF2196F3)),
    AccentPreset('Indigo', Color(0xFF3F51B5)),
    AccentPreset('Purple', Color(0xFF9C27B0)),
    AccentPreset('Pink', Color(0xFFE91E63)),
    AccentPreset('Teal', Color(0xFF009688)),
    AccentPreset('Green', Color(0xFF43A047)),
    AccentPreset('Orange', Color(0xFFF57C00)),
  ];

  static ThemeData light(Color accent) {
    final scheme = ColorScheme.fromSeed(seedColor: accent)
        .copyWith(primary: accent);
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
    );
  }

  static ThemeData dark(Color accent) {
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.dark,
    ).copyWith(primary: accent);
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
    );
  }

  /// Pitch-black theme for AMOLED screens: a true-black scaffold with
  /// near-black raised surfaces (dialogs, sheets, cards, menus) and the
  /// selected accent on top.
  static ThemeData pitchBlack(Color accent) {
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.dark,
    ).copyWith(
      primary: accent,
      surface: Colors.black,
      surfaceContainerLowest: Colors.black,
      surfaceContainerLow: const Color(0xFF0B0B0B),
      surfaceContainer: const Color(0xFF111111),
      surfaceContainerHigh: const Color(0xFF161616),
      surfaceContainerHighest: const Color(0xFF1C1C1C),
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: Colors.black,
      canvasColor: Colors.black,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.black,
        surfaceTintColor: Colors.transparent,
      ),
      dividerColor: Colors.white12,
    );
  }

  /// Background color for modal bottom sheets that follows the active
  /// theme: default in light, dark grey in Dark and near-black in
  /// Pitch Black.
  static Color? sheetBackground(BuildContext context) {
    final theme = Theme.of(context);
    if (theme.brightness == Brightness.light) return null;
    return theme.colorScheme.surfaceContainerLow;
  }

  /// Whether [preset] is the accent currently stored in settings.
  static bool isAccentSelected(int stored, Color preset) =>
      stored == preset.toARGB32();
}

/// A named accent color option.
class AccentPreset {
  final String name;
  final Color color;

  const AccentPreset(this.name, this.color);
}
