import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models.dart';
import '../storage_service.dart';
import '../update_service.dart';
import '../video_playback_service.dart';
import '../widgets.dart';
import 'home_screen.dart';
import 'library_screen.dart';
import 'menu_screen.dart';
import 'music_screen.dart';
import 'player_screen.dart';
import 'shorts_screen.dart';
import 'video_audio_screen.dart';

/// ═══════════════════════ MAIN SHELL (Bottom Pill Navbar) ═══════════════════════
///
/// Pages live in an [IndexedStack] so switching tabs never disposes them —
/// the Home and Music feeds keep their scroll position and content instead
/// of auto-refreshing every time the user comes back. Tab switches fade
/// and lift the new page in (disabled from Settings when the user prefers
/// instant switches).
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell>
    with SingleTickerProviderStateMixin {
  int _index = 0;
  bool _checkedForUpdate = false;

  /// Drives the tab-switch transition (fade + slight lift).
  late final AnimationController _tabTransition = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    value: 1.0,
  );

  /// Where the Shorts exit button lands — recomputed every build so service
  /// changes are respected. Priority: Home, then Music, then Library.
  int _shortsExitIndex = 0;

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

  @override
  void dispose() {
    _tabTransition.dispose();
    super.dispose();
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

  void _switchTab(int i) {
    if (i == _index) return;
    final animations =
        context.read<StorageService>().animationsEnabled;
    setState(() => _index = i);
    if (animations) {
      _tabTransition.forward(from: 0.0);
    } else {
      _tabTransition.value = 1.0;
    }
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
      // items.length here is the Shorts tab index (Home may precede it).
      final shortsIndex = items.length;
      items.add(_NavItem(
        Icons.play_circle_outline,
        Icons.play_circle_fill,
        'Shorts',
        ShortsScreen(
          active: _index == shortsIndex,
          onExit: () => _switchTab(_shortsExitIndex),
        ),
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

    // Shorts exit target: first of Home ▸ Music ▸ Library.
    const exitCandidates = {'Home', 'Music', 'Library'};
    final exitIndex =
        navItems.indexWhere((item) => exitCandidates.contains(item.label));
    _shortsExitIndex = exitIndex >= 0 ? exitIndex : 0;

    // The Shorts tab is immersive full-screen — navbar & mini player hide.
    final onShorts = navItems[_index].label == 'Shorts';

    // Tab transition: quick fade + upward settle of the incoming page.
    final tabAnimation = CurvedAnimation(
      parent: _tabTransition,
      curve: Curves.easeOutCubic,
    );

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: FadeTransition(
              opacity: tabAnimation,
              child: ScaleTransition(
                alignment: Alignment.topCenter,
                scale: Tween<double>(begin: 0.985, end: 1.0)
                    .animate(tabAnimation),
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
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 12,
            child: SafeArea(
              top: false,
              child: IgnorePointer(
                ignoring: onShorts,
                child: AnimatedOpacity(
                  opacity: onShorts ? 0.0 : 1.0,
                  duration: const Duration(milliseconds: 180),
                  child: _PillNavBar(
                    items: navItems,
                    currentIndex: _index,
                    onTap: _switchTab,
                  ),
                ),
              ),
            ),
          ),
          // Floating mini player — bottom right, above the pill navbar.
          // Slides up + fades in when a video is minimized into it and
          // slides away when closed.
          Positioned(
            right: 12,
            bottom: 92,
            child: SafeArea(
              top: false,
              child: IgnorePointer(
                ignoring: onShorts,
                child: AnimatedOpacity(
                  opacity: onShorts ? 0.0 : 1.0,
                  duration: const Duration(milliseconds: 180),
                  child: const _MiniPlayer(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ═══════════════════════ MINI PLAYER ═══════════════════════
///
/// A video closed with the back gesture keeps playing here — YouTube
/// style. The live video plays inside the card (not just a thumbnail),
/// and tapping the card reopens the full player page. The card slides
/// up + fades in when a video is minimized into it and slides away
/// when closed (instant when animations are off).
class _MiniPlayer extends StatefulWidget {
  const _MiniPlayer();

  @override
  State<_MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<_MiniPlayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
    value: 0.0,
  );

  /// Card content — kept alive while the close animation plays out.
  VideoItem? _video;
  bool _open = false;

  @override
  void initState() {
    super.initState();
    _anim.addStatusListener((status) {
      if (status == AnimationStatus.dismissed && mounted && !_open) {
        // Exit animation finished — collapse the card.
        setState(() => _video = null);
      }
    });
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vps = context.watch<VideoPlaybackService>();
    final animations =
        context.select<StorageService, bool>((s) => s.animationsEnabled);
    final target = vps.miniVisible && vps.currentVideo != null;

    if (target != _open) {
      _open = target;
      if (target) {
        _video = vps.currentVideo;
        if (animations) {
          _anim.forward(from: 0.0);
        } else {
          _anim.value = 1.0;
        }
      } else {
        if (animations) {
          _anim.reverse();
        } else {
          _anim.value = 0.0;
          _video = null;
        }
      }
    } else if (target) {
      _video = vps.currentVideo;
    }

    final video = _video;
    if (video == null) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final progress = vps.duration.inMilliseconds > 0
        ? (vps.position.inMilliseconds / vps.duration.inMilliseconds)
            .clamp(0.0, 1.0)
        : 0.0;

    final curved = CurvedAnimation(
      parent: _anim,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.35),
          end: Offset.zero,
        ).animate(curved),
        child: Material(
          color: theme.colorScheme.surfaceContainerHighest,
          elevation: 8,
          shadowColor: Colors.black54,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: _open
                ? () {
                    // Audio-only mode reopens the dedicated Now Playing
                    // screen; a normal video reopens the player page.
                    if (vps.audioOnlyMode) {
                      Navigator.push(
                        context,
                        pushPlayerRoute(
                          const VideoAudioScreen(),
                          animationsEnabled: animations,
                        ),
                      );
                    } else {
                      Navigator.push(
                        context,
                        pushPlayerRoute(
                          PlayerScreen(
                            video: vps.currentVideo ?? video,
                            download: vps.currentDownload,
                          ),
                          animationsEnabled: animations,
                        ),
                      );
                    }
                  }
                : null,
            child: SizedBox(
              width: 320,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
                    child: Row(
                      children: [
                        // The live video itself — same controller, keeps
                        // playing while minimized (like the YouTube app).
                        // Audio-only mode shows the thumbnail with an
                        // audio badge instead (the video track is off).
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(
                            width: 96,
                            height: 54,
                            child: vps.audioOnlyMode
                                ? Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      VideoThumbnail(
                                        videoId: video.id,
                                        fallbackUrl: video.thumbnailUrl,
                                        width: 96,
                                        height: 54,
                                        fit: BoxFit.cover,
                                      ),
                                      Container(
                                        color: Colors.black
                                            .withValues(alpha: 0.45),
                                        child: const Icon(
                                          Icons.headphones,
                                          color: Colors.white,
                                          size: 20,
                                        ),
                                      ),
                                    ],
                                  )
                                : vps.hasActiveVideo
                                    ? Video(
                                        controller: vps.controller,
                                        fit: BoxFit.cover,
                                        controls: NoVideoControls,
                                      )
                                    : Container(
                                        color: Colors.black,
                                        child: const Icon(Icons.videocam,
                                            color: Colors.white70),
                                      ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        // Title + channel
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                video.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                video.uploader,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Play / pause
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          iconSize: 22,
                          onPressed: () => vps.togglePlayPause(),
                          icon: Icon(
                            vps.isPlaying
                                ? Icons.pause_circle_filled
                                : Icons.play_circle_filled,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        // Close
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          iconSize: 20,
                          onPressed: () => vps.close(),
                          icon: Icon(
                            Icons.close,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Thin progress bar
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(14),
                    ),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 3,
                      backgroundColor: theme.colorScheme.surfaceContainerHigh,
                      valueColor: AlwaysStoppedAnimation(
                        theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
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
    final animations = context
        .select<StorageService, bool>((s) => s.animationsEnabled);
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
                duration:
                    animations ? const Duration(milliseconds: 200) : Duration.zero,
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
                    AnimatedSwitcher(
                      duration:
                          animations ? const Duration(milliseconds: 180) : Duration.zero,
                      transitionBuilder: (child, anim) => ScaleTransition(
                        scale: anim,
                        child: FadeTransition(
                          opacity: anim,
                          child: child,
                        ),
                      ),
                      child: Icon(
                        selected ? item.filled : item.outlined,
                        key: ValueKey('${item.label}_$selected'),
                        color: selected
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant,
                        size: 22,
                      ),
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
