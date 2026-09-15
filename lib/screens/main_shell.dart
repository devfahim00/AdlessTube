import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../storage_service.dart';
import '../update_service.dart';
import 'home_screen.dart';
import 'library_screen.dart';
import 'menu_screen.dart';
import 'music_screen.dart';
import 'shorts_screen.dart';

/// ═══════════════════════ MAIN SHELL (Bottom Pill Navbar) ═══════════════════════
///
/// Pages live in an [IndexedStack] so switching tabs never disposes them —
/// the Home and Music feeds keep their scroll position and content instead
/// of auto-refreshing every time the user comes back.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;
  bool _checkedForUpdate = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_checkedForUpdate) {
      _checkedForUpdate = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_checkForUpdate(showUpToDate: false));
      });
    }
  }

  Future<void> _checkForUpdate({required bool showUpToDate}) async {
    final update = await UpdateService.checkForUpdate();
    if (!mounted) return;
    if (update == null) {
      if (showUpToDate) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You already have the latest version.')),
        );
      }
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Update available'),
        content: Text('Version ${update.tag} is available.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Later'),
          ),
          FilledButton(
            onPressed: () async {
              await launchUrl(update.url, mode: LaunchMode.externalApplication);
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  /// Build the list of visible tabs based on enabled services.
  List<_NavItem> _buildNavItems(StorageService storage) {
    final items = <_NavItem>[];
    if (storage.isServiceEnabled(StorageService.serviceYoutube)) {
      items.add(const _NavItem(
        Icons.home_outlined,
        Icons.home,
        'Home',
        HomeScreen(),
      ));
    }
    if (storage.isServiceEnabled(StorageService.serviceShorts)) {
      items.add(const _NavItem(
        Icons.play_circle_outline,
        Icons.play_circle_fill,
        'Shorts',
        ShortsScreen(),
      ));
    }
    if (storage.isServiceEnabled(StorageService.serviceMusic)) {
      items.add(const _NavItem(
        Icons.music_note_outlined,
        Icons.music_note,
        'Music',
        MusicScreen(),
      ));
    }
    // Library & Menu always visible
    items.add(const _NavItem(
      Icons.video_library_outlined,
      Icons.video_library,
      'Library',
      LibraryScreen(),
    ));
    items.add(_NavItem(
      Icons.menu,
      Icons.menu,
      'Menu',
      MenuScreen(onCheckForUpdate: () => _checkForUpdate(showUpToDate: true)),
    ));
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    final navItems = _buildNavItems(storage);

    // Clamp index if services changed
    if (_index >= navItems.length) {
      _index = 0;
    }

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: IndexedStack(
              index: _index,
              children: [
                for (var i = 0; i < navItems.length; i++)
                  _LazyTab(
                    active: i == _index,
                    builder: (_) => navItems[i].page,
                  ),
              ],
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 12,
            child: SafeArea(
              top: false,
              child: _PillNavBar(
                items: navItems,
                currentIndex: _index,
                onTap: (i) => setState(() => _index = i),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Builds its page only once it has been visited for the first time, then
/// keeps it alive (state included) for the rest of the session.
class _LazyTab extends StatefulWidget {
  final bool active;
  final WidgetBuilder builder;

  const _LazyTab({required this.active, required this.builder});

  @override
  State<_LazyTab> createState() => _LazyTabState();
}

class _LazyTabState extends State<_LazyTab> {
  bool _built = false;

  @override
  void didUpdateWidget(covariant _LazyTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active && !_built) {
      setState(() => _built = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.active || _built) {
      return widget.builder(context);
    }
    return const SizedBox.shrink();
  }
}

class _NavItem {
  final IconData outlined;
  final IconData filled;
  final String label;
  final Widget page;

  const _NavItem(this.outlined, this.filled, this.label, this.page);
}

class _PillNavBar extends StatelessWidget {
  final List<_NavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _PillNavBar({
    required this.items,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(40),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.18),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(items.length, (i) {
          final selected = i == currentIndex;
          final item = items[i];
          return Expanded(
            child: GestureDetector(
              onTap: () => onTap(i),
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: selected
                      ? theme.colorScheme.primary.withValues(alpha: 0.14)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      selected ? item.filled : item.outlined,
                      color: selected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                      size: 22,
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
